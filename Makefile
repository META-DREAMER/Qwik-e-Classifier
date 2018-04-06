# Makefile for YOLO
# Created by Hammad Jutt, March 4 2018

PROG = YOLO

CC = g++
CPPFLAGS = -std=c++11 -Wall
OCV_INCLUDES = -I/usr/local/include/
OCV_LIBDIRS = -L/usr/local/lib 
OCV_LIBS =  -lopencv_core -lopencv_highgui -lopencv_imgproc 

TESTS = $(PROG)-test
TEST_RUNNER = testRunner

all: $(PROG).o
test: $(TESTS)

$(PROG).o: $(PROG).cpp
	$(CC) $(CPPFLAGS) $(OCV_LIBDIRS) $(OCV_INCLUDES) $(PROG).cpp -c -o $(PROG).o $(OCV_LIBS)

$(TESTS): $(TESTS).cpp $(TEST_RUNNER).o $(PROG).o
	$(CC) $(CPPFLAGS) $(PROG).o $(TEST_RUNNER).o $(TESTS).cpp -o $(TESTS)

$(TEST_RUNNER).o: $(TEST_RUNNER).cpp
	$(CC) $(CPPFLAGS) $(TEST_RUNNER).cpp -c -o $(TEST_RUNNER).o

clean:
	rm -f $(PROG) $(PROG).o $(TESTS) $(TEST_RUNNER).o