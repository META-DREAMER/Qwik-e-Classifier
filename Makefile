# Makefile for YOLO
# Created by Hammad Jutt, March 4 2018

PROG = YOLO

CC = g++
CPPFLAGS = -std=c++11 -Wall

TESTS = $(PROG)-test
TEST_RUNNER = testRunner

all: $(PROG).o
test: $(TESTS)

$(PROG).o: $(PROG).cpp
	$(CC) $(CPPFLAGS) $(PROG).cpp -c -o $(PROG).o

$(TESTS): $(TESTS).cpp $(TEST_RUNNER).o $(PROG).o
	$(CC) $(CPPFLAGS) $(PROG).o $(TEST_RUNNER).o $(TESTS).cpp -o $(TESTS)

$(TEST_RUNNER).o: $(TEST_RUNNER).cpp
	$(CC) $(CPPFLAGS) $(TEST_RUNNER).cpp -c -o $(TEST_RUNNER).o

clean:
	rm -f $(PROG).o $(TESTS) $(TEST_RUNNER).o