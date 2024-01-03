#include <SoftwareSerial.h>
#include <stdint.h>

#define FORCE_INLINE __attribute__((always_inline))

#define IS_COMMAND(x) (!((x) & 0x80))

#define BLUETOOTH_RX_PIN 4
#define BLUETOOTH_TX_PIN 5
#define BLUETOOTH_STATE A5

#define MOTOR_DIR_A 12
#define MOTOR_BRAKE_A 9
#define MOTOR_PWM_A 3

#define MOTOR_DIR_B 13
#define MOTOR_BRAKE_B 8
#define MOTOR_PWM_B 11

#define DISTANCE_VCC 2
#define DISTANCE_TRIG 7
#define DISTANCE_ECHO 6

#define ACK_RECEIVE 0x55
#define ACK_DONE 0xAA

#define DIRECTION_FORWARD 0
#define DIRECTION_BACKWARD 1
#define DIRECTION_LEFT 2
#define DIRECTION_RIGHT 3

SoftwareSerial bluetoothSerial(BLUETOOTH_RX_PIN, BLUETOOTH_TX_PIN); // RX, TX

bool isConnected;

uint8_t messageData[5];
uint8_t messageLength;
bool messageReceived;

inline void FORCE_INLINE testConnection()
{
  while(!bluetoothSerial.available());
  uint8_t testAck = bluetoothSerial.read();
  if (testAck == ACK_DONE) 
  {
    digitalWrite(LED_BUILTIN, LOW);
    bluetoothSerial.write(ACK_DONE);
  } 
  else 
    while(true);
}

void setup() 
{
  pinMode(BLUETOOTH_RX_PIN, INPUT);
  pinMode(BLUETOOTH_TX_PIN, OUTPUT);
  pinMode(BLUETOOTH_STATE, INPUT);

  pinMode(MOTOR_DIR_A, OUTPUT);
  pinMode(MOTOR_BRAKE_A, OUTPUT);
  pinMode(MOTOR_PWM_A, OUTPUT);
  
  pinMode(MOTOR_DIR_B, OUTPUT);
  pinMode(MOTOR_BRAKE_B, OUTPUT);
  pinMode(MOTOR_PWM_B, OUTPUT);

  pinMode(DISTANCE_VCC, OUTPUT);
  pinMode(DISTANCE_TRIG, OUTPUT);
  pinMode(DISTANCE_ECHO, INPUT);

  pinMode(LED_BUILTIN, OUTPUT);

  digitalWrite(MOTOR_DIR_A, LOW);
  digitalWrite(MOTOR_BRAKE_A, LOW);
  analogWrite(MOTOR_PWM_A, 0);

  digitalWrite(MOTOR_DIR_B, LOW);
  digitalWrite(MOTOR_BRAKE_B, LOW);
  analogWrite(MOTOR_PWM_B, 0);

  bluetoothSerial.begin(9600);

  digitalWrite(LED_BUILTIN, HIGH);
  
  digitalWrite(DISTANCE_VCC, HIGH);

  testConnection();
}

inline void FORCE_INLINE updateMessage()
{
  while (bluetoothSerial.available()) 
  {
    uint8_t curr = bluetoothSerial.read();
    if (curr == ACK_DONE) 
    {
      messageReceived = true;
      bluetoothSerial.write(ACK_RECEIVE);
    }
    else 
    {
      messageData[messageLength] = curr;
      messageLength = (messageLength + 1) % 5;
    }
  }
}

inline void FORCE_INLINE consumeMessage()
{
  messageLength = 0;
  messageReceived = false;
}

bool decodeDirection(uint8_t controlByte, uint8_t &direction)
{
  uint8_t moveType = (controlByte & 0x60) >> 5;
  uint8_t moveDirection = (controlByte & (1 << 4)) != 0;
  if (!moveType) 
    direction = moveDirection ? DIRECTION_BACKWARD : DIRECTION_FORWARD;
  else 
    direction = moveDirection ? DIRECTION_RIGHT : DIRECTION_LEFT;
  return moveType < 2;
}

float measureDistance()
{
  digitalWrite(DISTANCE_TRIG, LOW);
  delayMicroseconds(5);
  digitalWrite(DISTANCE_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(DISTANCE_TRIG, LOW);
  int duration = pulseIn(DISTANCE_ECHO, HIGH);
  return ((float) (duration >> 1)) / 29;
}

inline void FORCE_INLINE sendFloat(float x) 
{
  uint8_t *data = (uint8_t *) &x;
  for (uint8_t i = 0; i < 4; i++) 
    bluetoothSerial.write(data[i]);
}

inline void FORCE_INLINE processMovement()
{
  uint8_t direction;
  decodeDirection(messageData[0], direction);
  switch (direction) 
  {
    case DIRECTION_FORWARD:
      digitalWrite(MOTOR_DIR_A, LOW);
      digitalWrite(MOTOR_DIR_B, LOW);
      break;
    case DIRECTION_BACKWARD:
      digitalWrite(MOTOR_DIR_A, HIGH);
      digitalWrite(MOTOR_DIR_B, HIGH);
      break;
    case DIRECTION_LEFT:
      digitalWrite(MOTOR_DIR_A, LOW);
      digitalWrite(MOTOR_DIR_B, HIGH);
      break;
    case DIRECTION_RIGHT:
      digitalWrite(MOTOR_DIR_A, HIGH);
      digitalWrite(MOTOR_DIR_B, LOW);
    break;
  }
  analogWrite(MOTOR_PWM_A, messageData[1]);
  analogWrite(MOTOR_PWM_B, messageData[1]);
  delay(10);
  bluetoothSerial.write(ACK_DONE);
}

inline void FORCE_INLINE processMeasurement()
{
  float distance = measureDistance();
  sendFloat(distance);
  bluetoothSerial.write(ACK_DONE);
}

void loop() 
{
  if (!digitalRead(BLUETOOTH_STATE)) 
  {
    digitalWrite(MOTOR_PWM_A, LOW);
    digitalWrite(MOTOR_PWM_B, LOW);
    while(true);
    digitalWrite(LED_BUILTIN, HIGH);
  }
  updateMessage();
  if (messageReceived)
  {
    if (IS_COMMAND(messageData[0]))
      processMovement();
    else
      processMeasurement();
    consumeMessage();
  }
}
