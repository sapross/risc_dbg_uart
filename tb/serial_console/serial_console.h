#ifndef SERIAL_CONSOLE_H_
#define SERIAL_CONSOLE_H_

#include <queue>
#include <stdint.h>
#include <sys/types.h>
#include <termios.h>

unsigned int get_baudrate(int baudrate);

class serial_console_t
{
  public:
    serial_console_t(char *name);
    void tick(vluint64_t time, uint8_t *rx, uint8_t *tx);
    unsigned char done()
    {
        return quit;
    }
    int exit_code()
    {
        return err;
    }

  private:
    void send();
    void receive();
    int err            = 0;
    unsigned char quit = 0;

    struct termios config;
    int server_fd;
    int client_fd;

    uint8_t rx;
    uint8_t tx;
    std::queue<uint8_t> input;
    std::queue<uint8_t> output;
};

static const int baud_rate   = 3 * 10e6;
static const int baud_period = 333; // ns
static const int clk_rate    = 10e8;
static const int clk_period  = 10; // ns
static const int baud_ticks  = clk_rate / baud_rate;

enum uart_st { st_idle, st_start, st_data, st_stop };

#endif // SERIAL_CONSOLE_H_
