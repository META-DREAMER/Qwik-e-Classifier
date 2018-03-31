// Header file for YOLO.cpp
// Created by Hammad Jutt, March 3 2018

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
#define FEATURES_PER_CELL (NUM_CLASSES + 5)*BOXES_PER_CELL
#define CONFIDENCE_THRESHOLD 0.01
#define IOU_THRESHOLD 0.5
#define MAX_BOXES 10

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

int argMax(std::vector<float> in);

bool comparePredictions(Prediction a, Prediction b);

double iou(Box a, Box b);

std::vector<float> softmax(std::vector<float> in);

std::vector<Prediction> filterRedundantBoxes(
    std::vector<Prediction> predictions,
    float threshold,
    int limit);

#endif
