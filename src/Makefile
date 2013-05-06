CC=gcc
CFLAGS=-std=c99 -Wall -pedantic -O0 -g
CLIBS=-lnetconf
BIN=nuci

$(BIN): main.o
	$(CC) $(CLIBS) $(CFLAGS) -o $(BIN) main.o

main.o: main.c main.h
	$(CC) $(CLIBS) $(CFLAGS) -c -o main.o main.c

clean: oclean
	rm $(BIN)

oclean:
	rm *.o

