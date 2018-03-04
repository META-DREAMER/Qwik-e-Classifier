#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vector>
#include <algorithm>
#include <iostream>

#define INPUT_WIDTH 416
#define INPUT_HEIGHT 416

struct BoundingBox {
    float x;
    float y;
    float width;
    float height;
};

struct Prediction {
    int classIndex;
    float score;
    BoundingBox box;
};

const float anchors[] = {1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52};


double sigmoid(double x) {
    return 1 / (1 + exp(-x));
}

std::vector<double> softmax(std::vector<double> x) {
    double max = *max_element(x.begin(), x.end());
    
    double sum = 0.0;
    std::vector<double> out(x.size());

    for(std::vector<int>::size_type i = 0; i != x.size(); i++) {
        out[i] = exp(x[i] - max);
        sum += out[i];
    }

    for(std::vector<int>::size_type i = 0; i != x.size(); i++)
        out[i] /= sum;
    
    return out;
}


int main(int argc, char** argv) {
    printf("\nSigmoid(1): %f\n\n", sigmoid(1));

    static const double arr[] = {1.0, 2.0, 3.0, 4.0, 1.0, 2.0, 3.0};
    std::vector<double> vec (arr, arr + sizeof(arr) / sizeof(arr[0]) );
    vec = softmax(vec);
    printf("Softmax [1, 2, 3, 4, 1, 2, 3]: \n");
    for (std::vector<double>::const_iterator i = vec.begin(); i != vec.end(); ++i)
        std::cout << *i << ' ';

    printf("\n\n");
}
