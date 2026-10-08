import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// HC-08 expõe um "UART" BLE neste serviço/característica.
final Guid kServico = Guid('0000ffe0-0000-1000-8000-00805f9b34fb');
final Guid kCaracteristica = Guid('0000ffe1-0000-1000-8000-00805f9b34fb');

/// Mesmos limites do sketch do Arduino (MINIMO / MAXIMO / INICIAL).
class Junta {
  final String nome;
  final String letra;
  final IconData icone;
  final int min, max, inicial;
  double valor;
  Junta(this.nome, this.letra, this.icone, this.min, this.max, this.inicial)
      : valor = inicial.toDouble();
}

void main() => runApp(const BracoApp());

class BracoApp extends StatelessWidget {
  const BracoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Braço Robótico',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFFF8A3D),
      ),
      home: const TelaConexao(),
    );
  }
}

// ───────────────────────── Tela 1: procurar e conectar ─────────────────────────

class TelaConexao extends StatefulWidget {
  const TelaConexao({super.key});
  @override
  State<TelaConexao> createState() => _TelaConexaoState();
}

class _TelaConexaoState extends State<TelaConexao> {
  List<ScanResult> _resultados = [];
  bool _procurando = false;
  String? _conectandoId;
  StreamSubscription? _subResultados, _subScan;

  @override
  void initState() {
    super.initState();
    _subResultados = FlutterBluePlus.scanResults.listen((r) {
      // Mostra só dispositivos com nome; os que anunciam FFE0 vão para o topo.
      final lista = r.where((e) => e.device.platformName.isNotEmpty).toList()
        ..sort((a, b) => (_ehHc08(b) ? 1 : 0) - (_ehHc08(a) ? 1 : 0));
      setState(() => _resultados = lista);
    });
    _subScan = FlutterBluePlus.isScanning.listen((s) => setState(() => _procurando = s));
    _procurar();
  }

  bool _ehHc08(ScanResult r) =>
      r.advertisementData.serviceUuids.contains(kServico) ||
      r.device.platformName.toUpperCase().contains('HC-08');

  Future<void> _procurar() async {
    try {
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn(); // só funciona no Android; no iOS o usuário liga
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      _aviso('Não foi possível procurar: $e');
    }
  }

  Future<void> _conectar(BluetoothDevice d) async {
    setState(() => _conectandoId = d.remoteId.str);
    await FlutterBluePlus.stopScan();
    try {
      await d.connect(timeout: const Duration(seconds: 10), autoConnect: false);
      final servicos = await d.discoverServices();
      final carac = servicos
          .where((s) => s.uuid == kServico)
          .expand((s) => s.characteristics)
          .firstWhere((c) => c.uuid == kCaracteristica);

      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TelaControle(dispositivo: d, carac: carac),
      ));
      await d.disconnect();
    } on StateError {
      await d.disconnect();
      _aviso('Esse dispositivo não tem o serviço FFE0. É mesmo o HC-08?');
    } catch (e) {
      await d.disconnect();
      _aviso('Falha ao conectar: $e');
    } finally {
      if (mounted) setState(() => _conectandoId = null);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _subResultados?.cancel();
    _subScan?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conectar ao braço')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _procurando ? FlutterBluePlus.stopScan : _procurar,
        icon: Icon(_procurando ? Icons.stop : Icons.bluetooth_searching),
        label: Text(_procurando ? 'Parar' : 'Procurar'),
      ),
      body: Column(
        children: [
          if (_procurando) const LinearProgressIndicator(),
          Expanded(
            child: _resultados.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _procurando
                            ? 'Procurando dispositivos BLE…'
                            : 'Nada encontrado.\nConfira se o HC-08 está ligado (LED piscando) e toque em Procurar.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _resultados.length,
                    itemBuilder: (_, i) {
                      final r = _resultados[i];
                      final hc = _ehHc08(r);
                      final conectando = _conectandoId == r.device.remoteId.str;
                      return ListTile(
                        leading: Icon(hc ? Icons.precision_manufacturing : Icons.bluetooth,
                            color: hc ? Theme.of(context).colorScheme.primary : null),
                        title: Text(r.device.platformName),
                        subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm'),
                        trailing: conectando
                            ? const SizedBox(
                                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _conectandoId == null ? () => _conectar(r.device) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Tela 2: controle do braço ─────────────────────────

class TelaControle extends StatefulWidget {
  final BluetoothDevice dispositivo;
  final BluetoothCharacteristic carac;
  const TelaControle({super.key, required this.dispositivo, required this.carac});
  @override
  State<TelaControle> createState() => _TelaControleState();
}

class _TelaControleState extends State<TelaControle> {
  // Base 7 · Ombro 9 · Cotovelo 6 · Garra 5 (pinos definidos no Arduino)
  final juntas = [
    Junta('Base', 'B', Icons.rotate_right, 0, 180, 90),
    Junta('Ombro', 'O', Icons.north_east, 20, 160, 90),
    Junta('Cotovelo', 'C', Icons.turn_right, 0, 180, 90),
    Junta('Garra', 'G', Icons.back_hand, 10, 110, 60),
  ];
  Junta get garra => juntas[3];

  // Envio com fila de 1 posição por junta: nunca acumula comandos velhos.
  final Map<String, String> _pendentes = {};
  bool _enviando = false;
  final Map<String, DateTime> _ultimoEnvio = {};
  static const _intervalo = Duration(milliseconds: 60);

  StreamSubscription? _subConexao;

  @override
  void initState() {
    super.initState();
    _subConexao = widget.dispositivo.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Conexão perdida com o braço')));
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _subConexao?.cancel();
    super.dispose();
  }

  void _enviar(String chave, String comando, {bool forcar = false}) {
    final agora = DateTime.now();
    final ultimo = _ultimoEnvio[chave];
    if (!forcar && ultimo != null && agora.difference(ultimo) < _intervalo) return;
    _ultimoEnvio[chave] = agora;
    _pendentes[chave] = comando;
    _esvaziarFila();
  }

  Future<void> _esvaziarFila() async {
    if (_enviando) return;
    _enviando = true;
    try {
      while (_pendentes.isNotEmpty) {
        final chave = _pendentes.keys.first;
        final cmd = _pendentes.remove(chave)!;
        final semResposta = widget.carac.properties.writeWithoutResponse;
        await widget.carac.write(utf8.encode('$cmd\n'), withoutResponse: semResposta);
      }
    } catch (e) {
      _pendentes.clear();
      debugPrint('Erro ao enviar: $e');
    } finally {
      _enviando = false;
    }
  }

  void _mover(Junta j, double v, {bool forcar = false}) {
    setState(() => j.valor = v);
    _enviar(j.letra, '${j.letra}${v.round()}', forcar: forcar);
  }

  void _home() {
    setState(() {
      for (final j in juntas) {
        j.valor = j.inicial.toDouble();
      }
    });
    _pendentes.clear();
    _enviar('H', 'H', forcar: true);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dispositivo.platformName),
        actions: [
          IconButton(
            tooltip: 'Posição inicial',
            icon: const Icon(Icons.home),
            onPressed: _home,
          ),
          IconButton(
            tooltip: 'Desconectar',
            icon: const Icon(Icons.bluetooth_disabled),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final j in juntas.take(3)) _cartaoJunta(j),
            const SizedBox(height: 8),
            _cartaoGarra(cores),
          ],
        ),
      ),
    );
  }

  Widget _cartaoJunta(Junta j) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(j.icone, size: 20),
                const SizedBox(width: 8),
                Text(j.nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${j.valor.round()}°',
                    style: const TextStyle(fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => _mover(j, (j.valor - 5).clamp(j.min, j.max).toDouble(), forcar: true),
                ),
                Expanded(
                  child: Slider(
                    value: j.valor,
                    min: j.min.toDouble(),
                    max: j.max.toDouble(),
                    divisions: j.max - j.min,
                    onChanged: (v) => _mover(j, v),
                    onChangeEnd: (v) => _mover(j, v, forcar: true), // garante a posição final
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _mover(j, (j.valor + 5).clamp(j.min, j.max).toDouble(), forcar: true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoGarra(ColorScheme cores) {
    final g = garra;
    final abertura = (g.valor - g.min) / (g.max - g.min); // 0 = fechada, 1 = aberta
    return Card(
      color: cores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(g.icone, color: cores.onPrimaryContainer),
                const SizedBox(width: 8),
                Text('Garra',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: cores.onPrimaryContainer)),
                const Spacer(),
                Text('${(abertura * 100).round()}% aberta · ${g.valor.round()}°',
                    style: TextStyle(color: cores.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: 12),
            // Desenho simples da garra que abre e fecha junto com o slider
            SizedBox(
              height: 70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.rotate(
                    angle: -0.6 * abertura,
                    alignment: Alignment.bottomCenter,
                    child: _dedo(cores),
                  ),
                  SizedBox(width: 6 + 30 * abertura),
                  Transform.rotate(
                    angle: 0.6 * abertura,
                    alignment: Alignment.bottomCenter,
                    child: _dedo(cores),
                  ),
                ],
              ),
            ),
            Slider(
              value: g.valor,
              min: g.min.toDouble(),
              max: g.max.toDouble(),
              divisions: g.max - g.min,
              onChanged: (v) => _mover(g, v),
              onChangeEnd: (v) => _mover(g, v, forcar: true),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _mover(g, g.min.toDouble(), forcar: true),
                    icon: const Icon(Icons.compress),
                    label: const Text('Fechar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _mover(g, g.max.toDouble(), forcar: true),
                    icon: const Icon(Icons.open_in_full),
                    label: const Text('Abrir'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dedo(ColorScheme cores) => Container(
        width: 14,
        height: 60,
        decoration: BoxDecoration(
          color: cores.primary,
          borderRadius: BorderRadius.circular(7),
        ),
      );
}
