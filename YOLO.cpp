#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vector>
#include <algorithm>
#include <iostream>

#define INPUT_WIDTH 416
#define INPUT_HEIGHT 416
#define GRID_WIDTH 13
#define GRID_HEIGHT 13
#define CELL_SIZE 32
#define BOXES_PER_CELL 5
#define NUM_CLASSES 20

struct Box {
    float x;
    float y;
    float width;
    float height;
};

struct Prediction {
    int classIndex;
    float score;
    Box box;
};

const float anchors[] = {1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52};

/**
  Logistic sigmoid, normalizes x to between 0 and 1
*/
double sigmoid(double x) {
    return 1 / (1 + exp(-x));
}

/**
  Returns index of largest value in given vector
*/
int argMax(std::vector<double> in) {
    return std::distance(in.begin(), std::max_element(in.begin(), in.end()));
}

/**
  Calculates intersection-over-union overlap of two bounding boxes.
  Returns value between 0 and 1 representing how much overlap there is.
*/
float iou(Box a, Box b) {
    float areaA = a.width * a.height;
    if (areaA <= 0) return 0;

    float areaB = b.width * b.height;
    if (areaB <= 0) return 0;

    float minX = std::max(a.x, b.x);
    float minY = std::max(a.y, b.y);
    float maxX = std::min(a.x + a.width, b.x + b.width);
    float maxY = std::min(a.y + a.height, b.y + b.height);

    float intersectArea = std::max(maxY - minY, 0.f) * std::max(maxX - minX, 0.f);

    return intersectArea / (areaA + areaB - intersectArea);
}

/**
  Normalizes all values in the given vector
  so that they all add up to 1.
*/
std::vector<double> softmax(std::vector<double> in)
{
    std::vector<double> out(in.size());
    double sum = 0.0;

    // Find max value in the input vector
    double max = *std::max_element(in.begin(), in.end());    

    // Shift all values so that max value is 0 and exponentiate, compute sum
    for(std::vector<int>::size_type i = 0; i != in.size(); i++) {
        out[i] = exp(in[i] - max);
        sum += out[i];
    }

    // Divide each element by the sum to normalize all values
    for(std::vector<int>::size_type i = 0; i != out.size(); i++)
        out[i] /= sum;
    
    return out;
}


int main(int argc, char** argv) {
    printf("\n\nSigmoid(1): %f\n\n", sigmoid(1));

    static const double arr[] = {1.0, 2.0, 3.0, 4.0, 1.0, 2.0, 3.0};
    std::vector<double> vec (arr, arr + sizeof(arr) / sizeof(arr[0]) );
    std::vector<double> softVec = softmax(vec);
    printf("Softmax [1, 2, 3, 4, 1, 2, 3]: \n");
    for (std::vector<double>::const_iterator i = softVec.begin(); i != softVec.end(); ++i)
        std::cout << *i << ' ';

    printf("\n\nArgmax [1, 2, 3, 4, 1, 2, 3]: %d\n\n", argMax(vec));
}
