CC ?= gcc
CFLAGS ?= -O3 -ffast-math -Wall -Wextra -fPIC -Iinclude -Isrc
LDFLAGS ?= -shared -lm

LIB_TARGET = libl2hc.so
STATIC_TARGET = libl2hc.a

SRCS = src/l2hc_native.c
OBJS = $(SRCS:.c=.o)

all: $(LIB_TARGET) $(STATIC_TARGET) tests

$(LIB_TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

$(STATIC_TARGET): $(OBJS)
	ar rcs $@ $^

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

tests: tests/test_benchmark tests/test_correctness

tests/test_benchmark: tests/test_benchmark.c $(LIB_TARGET)
	$(CC) $(CFLAGS) $< -L. -ll2hc -lm -Wl,-rpath,. -o $@

tests/test_correctness: tests/test_correctness.c $(LIB_TARGET)
	$(CC) $(CFLAGS) $< -L. -ll2hc -lm -Wl,-rpath,. -o $@

check: tests
	./tests/test_correctness
	./tests/test_benchmark

clean:
	rm -f $(LIB_TARGET) $(STATIC_TARGET) src/*.o tests/test_benchmark tests/test_correctness
	rm -rf dist build_deb

.PHONY: all tests check clean
