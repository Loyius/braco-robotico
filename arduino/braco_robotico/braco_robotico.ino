/*
  Braço robótico — Arduino Uno + HC-08 (BLE) + 4 microservos

  Pinos dos servos:  Base D7 | Ombro D9 | Cotovelo D6 | Garra D5
  HC-08:             TX -> D2   |   RX <- D3 (com divisor de tensão 5V -> 3,3V)

  Protocolo (texto, uma linha por comando, termina com \n):
    B<angulo>  base        ex: B90
    O<angulo>  ombro       ex: O45
    C<angulo>  cotovelo    ex: C120
    G<angulo>  garra       ex: G30
    H          volta para a posição inicial (home)

  Também aceita os mesmos comandos pelo Monitor Serial (9600, "Nova linha"),
  útil para testar sem o celular.
*/

#include <Servo.h>
#include <SoftwareSerial.h>

SoftwareSerial ble(2, 3); // RX do Arduino (liga no TX do HC-08), TX do Arduino (liga no RX do HC-08)

const int NUM = 4;
//                         Base  Ombro  Cotovelo  Garra
const char LETRAS[NUM]  = { 'B',  'O',   'C',      'G' };
const byte PINOS[NUM]   = {  7,    9,     6,        5  };
// Ajuste estes limites depois de testar a mecânica do seu braço,
// e use os MESMOS valores no app (lib/main.dart -> lista "juntas").
const int  MINIMO[NUM]  = {  0,   20,     0,       10  };
const int  MAXIMO[NUM]  = { 180, 160,   180,      110  };
const int  INICIAL[NUM] = {  90,  90,    90,       60  };

Servo servos[NUM];
int atual[NUM];
int alvo[NUM];

// Velocidade: ms entre cada grau. Maior = mais suave/lento e menos pico de corrente.
const unsigned long PASSO_MS = 12;
unsigned long ultimoPasso = 0;

char bufBle[16];    byte tamBle = 0;
char bufSerial[16]; byte tamSerial = 0;

void processar(char *cmd) {
  char letra = toupper(cmd[0]);

  if (letra == 'H') {
    for (int i = 0; i < NUM; i++) alvo[i] = INICIAL[i];
    Serial.println(F("HOME"));
    return;
  }

  if (!isDigit(cmd[1])) return;           // ignora lixo
  int angulo = atoi(cmd + 1);

  for (int i = 0; i < NUM; i++) {
    if (LETRAS[i] == letra) {
      alvo[i] = constrain(angulo, MINIMO[i], MAXIMO[i]);
      Serial.print(letra);
      Serial.print(F(" -> "));
      Serial.println(alvo[i]);
      return;
    }
  }
}

// Lê caracteres de uma porta e executa cada linha completa
void lerEntrada(Stream &porta, char *buf, byte &tam, byte capacidade) {
  while (porta.available()) {
    char c = porta.read();
    if (c == '\n' || c == '\r') {
      if (tam > 0) {
        buf[tam] = '\0';
        processar(buf);
        tam = 0;
      }
    } else if (tam < capacidade - 1) {
      buf[tam++] = c;
    } else {
      tam = 0; // linha grande demais, descarta
    }
  }
}

void moverSuave() {
  if (millis() - ultimoPasso < PASSO_MS) return;
  ultimoPasso = millis();

  for (int i = 0; i < NUM; i++) {
    if (atual[i] < alvo[i])      atual[i]++;
    else if (atual[i] > alvo[i]) atual[i]--;
    else continue;
    servos[i].write(atual[i]);
  }
}

void setup() {
  Serial.begin(9600);
  ble.begin(9600); // baud padrão do HC-08

  for (int i = 0; i < NUM; i++) {
    atual[i] = alvo[i] = INICIAL[i];
    servos[i].write(INICIAL[i]);  // define a posição ANTES de ligar o pulso (evita tranco)
    servos[i].attach(PINOS[i]);
    delay(250);                   // liga um servo por vez para não derrubar a alimentação
  }

  Serial.println(F("Braco pronto. Comandos: B90, O45, C120, G30, H"));
}

void loop() {
  lerEntrada(ble, bufBle, tamBle, sizeof(bufBle));
  lerEntrada(Serial, bufSerial, tamSerial, sizeof(bufSerial));
  moverSuave();
}
