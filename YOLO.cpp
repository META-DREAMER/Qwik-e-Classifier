/*
  Implementation of tiny-yolo algorithm (https://pjreddie.com/darknet/yolo/)
  Created by Hammad Jutt, March 3 2018

  References used:
  - https://github.com/pjreddie/darknet
  - https://github.com/joycex99/tiny-yolo-keras/
  - https://github.com/tensorflow/tensorflow/blob/master/tensorflow/core/kernels/non_max_suppression_op.cc
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vector>
#include <algorithm>
#include <iostream>

#include "YOLO.hpp"

const float anchors[] = {1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52};

/**
  Logistic sigmoid, normalizes x to between 0 and 1
*/
double sigmoid(double x)
{
    return 1 / (1 + exp(-x));
}

/**
  Returns index of largest value in given vector
*/
int argMax(std::vector<double> in)
{
    return std::distance(in.begin(), std::max_element(in.begin(), in.end()));
}

/**
  Comparator function for sorting predictions
*/
bool comparePredictions (Prediction a, Prediction b)
{
    return (a.score > b.score);
}

/**
  Calculates intersection-over-union overlap of two bounding boxes.

  Parameters:
    - a: The first bounding box
    - b: The second bounding box
  Returns:
    - value between 0 and 1 representing how much overlap there is
*/
double iou(Box a, Box b)
{
    double areaA = a.width * a.height;
    if (areaA <= 0)
        return 0;

    double areaB = b.width * b.height;
    if (areaB <= 0)
        return 0;

    double minX = std::max(a.x, b.x);
    double minY = std::max(a.y, b.y);
    double maxX = std::min(a.x + a.width, b.x + b.width);
    double maxY = std::min(a.y + a.height, b.y + b.height);

    double intersectArea = std::max(maxY - minY, 0.0) * std::max(maxX - minX, 0.0);

    return intersectArea / (areaA + areaB - intersectArea);
}

/**
  Normalizes all values in the given vector
  so that they all add up to 1.

  Parameters:
    - in: a vector of values to normalize
  Returns:
    - a vector containing the softmaxed values
*/
std::vector<double> softmax(std::vector<double> in)
{
    if (in.size() <= 0) return in;

    std::vector<double> out(in.size());
    double sum = 0.0;

    // Find max value in the input vector
    double max = *std::max_element(in.begin(), in.end());

    // Shift all values so that max value is 0 and exponentiate, compute sum
    for (std::vector<int>::size_type i = 0; i != in.size(); i++)
    {
        out[i] = exp(in[i] - max);
        sum += out[i];
    }

    // Divide each element by the sum to normalize all values
    for (std::vector<int>::size_type i = 0; i != out.size(); i++)
        out[i] /= sum;

    return out;
}

/**
  Removes bounding boxes that have too much overlap
  with other bounding boxes that have a higher score.

  Parameters:
    - predictions: an vector of bounding boxes and their scores
    - threshold: value between 0 and 1 to determine whether a box overlaps too much
    - limit: the maximum number of boxes to select
  Returns:
    - a vector containing the resulting bounding boxes
*/
std::vector<Prediction> filterRedundantBoxes(
    std::vector<Prediction> predictions,
    float threshold,
    int limit)
{
    // Sort based on confidence score
    std::vector<Prediction> sorted = predictions;
    std::sort (sorted.begin(), sorted.end(), comparePredictions);

    std::vector<Prediction> selected;
    std::vector<bool> active(sorted.size(), true);
    int numActive = active.size();

    // Starting at highest scoring box, remove all other boxes
    // that overlap more than the given threshold. Repeat until
    // limit is reached or no other boxes remain;
    for (std::vector<int>::size_type i = 0; i != sorted.size(); i++)
    {
        if (!active[i]) continue;

        Prediction a = sorted[i];
        selected.push_back(a);
        if (selected.size() >= limit) { break; }
        for (std::vector<int>::size_type j = i+1; j != sorted.size(); j++)
        {
            if (!active[j]) continue;
            
            Prediction b = sorted[j];
            if (iou(a.box, b.box) > threshold) {
                active[j] = false;
                numActive -= 1;
                if (numActive <= 0) { goto finish; }
            }
        }
    }

finish:
    return selected;
}
