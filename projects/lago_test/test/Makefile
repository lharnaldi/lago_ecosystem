
SENSOR=bmp180

all:
	gcc -Wall -c $(SENSOR).c -o $(SENSOR).o -lm
	gcc -Wall $(SENSOR).o test.c -o test -lm

clean:
	rm *.o > /dev/null 2>&1 &
