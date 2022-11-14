#include <assert.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>

#include "serial_console.h"

#include <queue>
#include <pty.h>
#include <stdint.h>
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <strings.h>

serial_console_t::serial_console_t(char *name, int baudrate)
    : err(0), quit(0), server_fd(0), client_fd(0)
{
    auto bdcode = get_baudrate(baudrate);
    if (bdcode == 0) {
        fprintf(stderr, "serial_console failed. Invalid Baudrate:(%d)\n",
                baudrate);
        abort();
    }

    bzero(&config, sizeof(config));
    cfmakeraw(&config);
    config.c_cflag |= bdcode;
    // Read will return immediatly, whether data is available or not.
    config.c_cc[VMIN]  = 0;
    config.c_cc[VTIME] = 0;
    if (!openpty(&server_fd, &client_fd, name, &config, NULL)) {
        fprintf(stderr, "serial_console failed openpty: %s (%d)\n",
                strerror(errno), errno);
        abort();
    };
    err  = 1;
    quit = 1;
}

void serial_console_t::send(vluint64_t time)
{

    static vluint64_t last_time;
    static enum uart_st state = st_idle;
    static uint8_t current    = 0;
    static size_t data_index  = 0;

    switch (state) {
    case (st_idle):
        tx = 1;
        if (output.size() > 0) {
            current   = output.pop();
            state     = st_start;
            last_time = time;
        }
        break;
    case (st_start):
        tx = 0;
        if (time - last_time > baud_ticks) {
            last_time = time;
            state     = st_data;
        }
        break;
    case (st_data):
        tx = (current >> data_index) & 1u;
        if (time - last_time > baud_ticks) {
            last_time = time;
            data_index++;
            if (data_index >= 8) {
                state = st_stop;
            }
        }
        break;
    case (st_stop):
        tx = 1;
        if (time - last_time > baud_ticks) {
            state = st_idle;
        }
        break;
    }
}

void serial_console_t::receive(vluint64_t time)
{

    static vluint64_t last_time;
    static enum uart_st state = st_idle;
    static uint8_t current    = 0;
    static size_t data_index  = 0;
    static uint8_t rx_prev    = 1;

    switch (state) {
    case (st_idle):
        if (rx_prev == 1 && rx == 0) {
            state     = st_start;
            last_time = time;
        }
        break;
    case (st_start):
        if (time - last_time > 3 * baud_ticks / 2) {
            last_time = time;
            state     = st_data;
            current   = 0;
        }
        break;
    case (st_data):
        current |= rx << data_index;
        if (time - last_time > baud_ticks) {
            last_time = time;
            data_index++;
            if (data_index >= 8) {
                state = st_stop;
            }
        }
        break;
    case (st_stop):
        if (time - last_time > baud_ticks / 2) {
            state = st_idle;
        }
        break;
    }
    rx_prev = rx;
}
void serial_console_t::tick(vluint64_t time, uint8_t *rx, uint8_t *tx)
{
    char data;
    ssize_t len = read(server_fd, &data, 1);
    if (len == 1) {
        input.enqueue(data);
    } else if (len == -1) {
        fprintf(stderr, "Error reading from serial interace.");
    }
    send(time);
    receive(time);
    if (output.size() > 0) {
        data = output.pop();
        write(server_fd, &data, 1);
    }
    *rx = this->rx;
    *tx = this->tx;
}

unsigned int get_baudrate(int bd)
{
    if (bd == 300) {
        return B300;
    }
    if (bd == 600) {
        return B600;
    }
    if (bd == 1200) {
        return B1200;
    }
    if (bd == 2400) {
        return B2400;
    }
    if (bd == 4800) {
        return B4800;
    }
    if (bd == 9600) {
        return B9600;
    }
    if (bd == 19200) {
        return B19200;
    }
    if (bd == 38400) {
        return B38400;
    }
    if (bd == 57600) {
        return B57600;
    }
    if (bd == 115200) {
        return B115200;
    }
    if (bd == 230400) {
        return B230400;
    }
    if (bd == 460800) {
        return B460800;
    }
    if (bd == 576000) {
        return B57600;
    }
    if (bd == 921600) {
        return B921600;
    }
    if (bd == 1000000) {
        return B1000000;
    }
    if (bd == 2000000) {
        return B2000000;
    }
    if (bd == 3000000) {
        return B3000000;
    }
    return 0;
}
