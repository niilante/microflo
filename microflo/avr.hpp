/* MicroFlo - Flow-Based Programming for microcontrollers
 * Copyright (c) 2013 Jon Nordby <jononor@gmail.com>
 * MicroFlo may be freely distributed under the MIT license
 */

#include "microflo.h"

#include <avr/io.h>
#include <util/atomic.h>

// Datasheets
// atmega328: http://www.atmel.com/Images/Atmel-8271-8-bit-AVR-Microcontroller-ATmega48A-48PA-88A-88PA-168A-168PA-328-328P_datasheet.pdf
// at90usb1287: http://www.atmel.com/Images/doc7593.pdf
// at90usbkey: http://www.atmel.com/Images/doc7627.pdf‎

// Those not familiar with bitmasking and register twiddling should see
// http://www.avrfreaks.net/index.php?name=PNphpBB2&file=printview&t=37871

// Timers, see
// http://www.adnbr.co.uk/articles/counting-milliseconds


#ifndef F_CPU
#error "F_CPU not defined!"
#endif

#define MILLISECOND_OVERFLOW ((F_CPU / 1000) / 8)

#define avrPinSet(REG, pinNumber) *ports[pinNumber/8].REG |= _BV(pinNumber % 8)
#define avrPinClear(REG, pinNumber) *ports[pinNumber/8].REG &= ~_BV(pinNumber % 8)
#define avrPinGet(REG, pinNumber) *ports[pinNumber/8].REG & _BV(pinNumber % 8)

struct AvrPort {
    volatile uint8_t * DDR;
    volatile uint8_t * PIN;
    volatile uint8_t * PORT;
};

// PERFORMANCE: use a C++ const-expression for the pin to register mapping?

static const AvrPort ports[6] = {
    {&DDRA, &PINA, &PORTA},
    {&DDRB, &PINB, &PORTB},
    {&DDRC, &PINC, &PORTC},
    {&DDRD, &PIND, &PORTD},
    {&DDRE, &PINE, &PORTE},
    {&DDRF, &PINF, &PORTF},
};

static volatile long g_millis = 0;

ISR (TIMER1_COMPA_vect)
{
    g_millis++;
}

class Avr8IO : public IO {
public:


public:
    Avr8IO() {
        // Clear on match mode, Clock/8
        TCCR1B = (1 << WGM12) | (1 << CS11);
        // Overflow every 1ms, enable interrupt
        OCR1AH = (MILLISECOND_OVERFLOW >> 8);
        OCR1AL = MILLISECOND_OVERFLOW;
        TIMSK1 |= (1 << OCIE1A);
    }
    ~Avr8IO() {
    }

    // Serial
    // FIXME: implement
    virtual void SerialBegin(uint8_t serialDevice, int baudrate) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
    }
    virtual long SerialDataAvailable(uint8_t serialDevice) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
        return false;
    }
    virtual unsigned char SerialRead(uint8_t serialDevice) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
        return 0;
    }
    virtual void SerialWrite(uint8_t serialDevice, unsigned char b) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
    }

    // Pin config
    virtual void PinSetMode(MicroFlo::PinId pin, IO::PinMode mode) {
        if (mode == IO::OutputPin) {
            avrPinSet(DDR, pin);
        } else if (mode == IO::InputPin) {
            avrPinClear(DDR, pin);
        }
    }
    virtual void PinSetPullup(MicroFlo::PinId pin, IO::PullupMode mode) {
        // assumes pin has been configured as input
        if (mode == IO::PullUp) {
            avrPinSet(PORT, pin);
        } else if (mode == IO::PullNone) {
            avrPinClear(PORT, pin);
        } else {
            MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
        }
    }

    // Digital
    virtual void DigitalWrite(MicroFlo::PinId pin, bool val) {
        if (val)
            avrPinSet(PORT, pin);
        else
            avrPinClear(PORT, pin);
    }
    virtual bool DigitalRead(MicroFlo::PinId pin) {
        return avrPinGet(PIN, pin);
    }

    // Analog
    // FIXME: implement
    virtual long AnalogRead(MicroFlo::PinId pin) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
        return 0;
    }
    virtual void PwmWrite(MicroFlo::PinId pin, long dutyPercent) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
    }

    // Timer
    // FIXME: implement
    virtual long TimerCurrentMs() {
        long millis;
        ATOMIC_BLOCK(ATOMIC_FORCEON) {
            millis = g_millis;
        }
        return millis;
    }

    virtual void AttachExternalInterrupt(uint8_t interrupt, IO::Interrupt::Mode mode,
                                         IOInterruptFunction func, void *user) {
        MICROFLO_DEBUG(debug, DebugLevelError, DebugIoOperationNotImplemented);
    }
};

