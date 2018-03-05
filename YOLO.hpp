#ifndef YOLO_H
#define YOLO_H

#include <vector>

#define INPUT_WIDTH 416
#define INPUT_HEIGHT 416
#define GRID_WIDTH 13
#define GRID_HEIGHT 13
#define CELL_SIZE 32
#define BOXES_PER_CELL 5
#define NUM_CLASSES 20

struct Box
{
    float x;
    float y;
    float width;
    float height;
};

struct Prediction
{
    int classIndex;
    float score;
    Box box;
};

double sigmoid(double x);

int argMax(std::vector<double> in);

bool comparePredictions(Prediction a, Prediction b);

double iou(Box a, Box b);

std::vector<double> softmax(std::vector<double> in);

std::vector<Prediction> filterRedundantBoxes(
    std::vector<Prediction> predictions,
    float threshold,
    int limit);

#endif
