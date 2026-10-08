# Braço robótico — Arduino Uno + HC-08 + app Flutter

```
braco-robotico/
├── arduino/braco_robotico/braco_robotico.ino   ← sketch do Uno
└── app/                                         ← app Flutter (Android e iOS)
    ├── pubspec.yaml
    ├── lib/main.dart
    └── android-permissoes.xml
```

## 1. Ligações

| Componente      | Pino no Arduino | Observação |
|-----------------|-----------------|------------|
| Servo Base      | D7              | sinal (fio laranja/amarelo) |
| Servo Ombro     | D9              | |
| Servo Cotovelo  | D6              | |
| Servo Garra     | D5              | |
| HC-08 TX        | D2              | direto |
| HC-08 RX        | D3              | **via divisor de tensão** (1 kΩ do D3 → RX, 2 kΩ do RX → GND) |
| HC-08 VCC / GND | 5V / GND        | conferir na placa do seu módulo (a maioria aceita 3,6–6 V) |

**Alimentação dos servos:** não ligue os 4 servos no 5V do Uno. Quando mexem juntos
puxam mais corrente do que a placa aguenta, o Arduino reinicia e o Bluetooth cai.
Use uma fonte externa de 5–6 V / 2 A (ou 4 pilhas AA) para o vermelho dos servos e
**una o GND da fonte com o GND do Arduino**.

Os pinos D2/D3 ficaram para o HC-08 porque assim o D0/D1 (USB) fica livre:
dá para enviar o sketch sem desconectar o módulo e testar pelo Monitor Serial.

## 2. Arduino

1. Abra `braco_robotico.ino` na Arduino IDE (bibliotecas `Servo` e `SoftwareSerial` já vêm instaladas).
2. Envie para o Uno.
3. Teste sem o celular: Monitor Serial a 9600, final de linha "Nova linha", digite `G30`, `G100`, `B45`, `H`.
4. Ajuste `MINIMO`/`MAXIMO` de cada junta para os limites reais da sua montagem
   (principalmente a garra, para não forçar o servo quando ela fecha). Repita os mesmos
   valores na lista `juntas` em `app/lib/main.dart`.

### Protocolo

Texto simples, um comando por linha: `B<ângulo>`, `O<ângulo>`, `C<ângulo>`, `G<ângulo>`, `H` (home).
O Arduino limita cada ângulo à faixa da junta e move os servos 1° por vez (movimento suave).

## 3. App (Flutter)

O HC-08 é **Bluetooth Low Energy**, então ele não aparece na lista de pareamento do celular
e apps de Bluetooth clássico (feitos para HC-05/HC-06) não conectam nele. O app usa
BLE pelo serviço `FFE0` / característica `FFE1` e funciona em Android e iPhone.

```bash
cd app
flutter create --platforms=android,ios --project-name braco_robotico .
flutter pub get
```

O `flutter create .` gera as pastas `android/` e `ios/` sem sobrescrever `lib/main.dart` e `pubspec.yaml`.

**Android:** cole o conteúdo de `android-permissoes.xml` no
`android/app/src/main/AndroidManifest.xml` (acima de `<application>`) e, em
`android/app/build.gradle`, use `minSdkVersion 21` ou maior.

**iOS:** em `ios/Runner/Info.plist`, adicione:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Usado para controlar o braço robótico</string>
```

Depois, com o celular conectado no USB:

```bash
flutter run
```

### Usando

1. Ligue o braço (o LED do HC-08 pisca).
2. Abra o app, ele já procura sozinho. O HC-08 aparece no topo com ícone de braço.
3. Toque nele. Na tela de controle: sliders e botões ±5° para base, ombro e cotovelo;
   cartão da garra com slider e botões **Abrir**/**Fechar**; botão 🏠 volta tudo para a posição inicial.

## Problemas comuns

- **Arduino reinicia / conexão cai quando os servos mexem** → alimentação (ver seção 1).
- **Conecta mas o braço não mexe** → TX/RX trocados ou baud diferente de 9600 no HC-08.
- **"Não tem o serviço FFE0"** → o dispositivo tocado não é o HC-08 (alguns clones usam outro UUID;
  troque `kServico`/`kCaracteristica` no topo de `main.dart`).
- **Servo tremendo parado** → GND da fonte externa não está unido ao GND do Arduino.
