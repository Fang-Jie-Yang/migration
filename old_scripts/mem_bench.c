#include <stdio.h>
#include <stdlib.h>

int main()
{
    char *arr = (char *)malloc(sizeof(char) * 4096 * 4096);
    char now = 0;
    while(1)
    {
        now += 1;
        now %= 255;
        for(int i = 0; i < 4096 * 4096; i++)
        {
            arr[i] = now;
        }
    }
}
