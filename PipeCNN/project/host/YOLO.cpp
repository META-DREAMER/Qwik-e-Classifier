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
#include <fstream>
#include "YOLO.hpp"


const float anchors[] = {1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52};
const std::string labels[] = { "aeroplane","bicycle","bird","boat","bottle","bus","car","cat","chair","cow","diningtable","dog","horse","motorbike","person","pottedplant","sheep","sofa","train","tvmonitor"};

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
int argMax(std::vector<float> in)
{
    return std::distance(in.begin(), std::max_element(in.begin(), in.end()));
}

/**
  Comparator function for sorting predictions
*/
bool comparePredictions(Prediction a, Prediction b)
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
std::vector<float> softmax(std::vector<float> in)
{
    if (in.size() <= 0)
        return in;

    std::vector<float> out(in.size());
    float sum = 0.0;

    // Find max value in the input vector
    float max = *std::max_element(in.begin(), in.end());

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
    uint limit)
{
    // Sort based on confidence score
    std::vector<Prediction> sorted = predictions;
    std::sort(sorted.begin(), sorted.end(), comparePredictions);

    std::vector<Prediction> selected;
    std::vector<bool> active(sorted.size(), true);
    int numActive = active.size();

    // Starting at highest scoring box, remove all other boxes
    // that overlap more than the given threshold. Repeat until
    // limit is reached or no other boxes remain;
    for (std::vector<int>::size_type i = 0; i != sorted.size(); i++)
    {
        if (!active[i])
            continue;

        Prediction a = sorted[i];
        selected.push_back(a);
        if (selected.size() >= limit)
        {
            break;
        }
        for (std::vector<int>::size_type j = i + 1; j != sorted.size(); j++)
        {
            if (!active[j])
                continue;

            Prediction b = sorted[j];
            if (iou(a.box, b.box) > threshold)
            {
                active[j] = false;
                numActive -= 1;
                if (numActive <= 0)
                {
                    goto finish;
                }
            }
        }
    }

finish:
    return selected;
}

/**
  Removes bounding boxes that have too much overlap
  with other bounding boxes that have a higher score.

  Parameters:
    - features: a 3D vector containing raw output data from the network
  Returns:
*/
std::vector<Prediction> interpretNetworkOutput(float ***features) {
    std::vector<Prediction> predictions;

    for (int cy = 0; cy != GRID_HEIGHT; cy++) {
        for (int cx = 0; cx != GRID_WIDTH; cx++) {
            for (int b = 0; b != BOXES_PER_CELL; b++) {
                // First box features: 0-24, second box features: (25-49), etc
                int offset = b*(NUM_CLASSES + 5);

                // extract bounding box data from feature array
                float bx = features[cy][cx][offset + 0];
                float by = features[cy][cx][offset + 1];
                float bw = features[cy][cx][offset + 2];
                float bh = features[cy][cx][offset + 3];
                float bc = features[cy][cx][offset + 4];

                
                // convert cell coords to coords in original image
                float x = ((float)cx + sigmoid(bx)) * CELL_SIZE;
                float y = ((float)cy + sigmoid(by)) * CELL_SIZE;

                // box sizes relative to anchor, convert to width/height in original image
                float w = expf(bw) * anchors[2*b + 0] * CELL_SIZE;
                float h = expf(bh) * anchors[2*b + 1] * CELL_SIZE;

                // convert confidence to percentage
                float confidence = sigmoid(bc);

                // printf("x: %f, y: %f, w: %f, h: %f, c: %f\n", x, y, w, h, confidence);
                // extract classes from feature array and convert to percentages
                std::vector<float> classes(NUM_CLASSES, 0.f);
                for (std::vector<float>::size_type i = 0; i != classes.size(); i++) {
                    classes[i] = features[cy][cx][offset + 5 + i];
                }
                classes = softmax(classes);

                // find best class
                int bestClassIdx = argMax(classes);
                float bestClassScore = classes[bestClassIdx];
    
                // combine confidence of bounding box with confidence of class
                float classConfidence = bestClassScore * confidence;

                // Only keep results that meet threshold
                if (classConfidence > CONFIDENCE_THRESHOLD) {
                    Box bounds = {};
                    bounds.x = x - w/2; bounds.width = w;
                    bounds.y = y - h/2; bounds.height = h;
                    
                    Prediction pred = {};
                    pred.box = bounds;
                    pred.classIndex = bestClassIdx;
                    pred.score = classConfidence;

                    predictions.push_back(pred);
                }
            }
        }
    }

    return filterRedundantBoxes(predictions, IOU_THRESHOLD, MAX_BOXES);
}


float *** readResults(){
    std::ifstream result_file ("PipeCNN/project/result_dump.txt", std::ios::in);

    if (!result_file.is_open()) {
        printf("Unable to open results file\n");
        exit(-1);
    }
    
    int xDim;
    int yDim;
    int zDim;
    result_file >> xDim;
    result_file >> yDim;
    result_file >> zDim;

    float *** array = new float**[xDim];

    for(int x=0; x<xDim; x++){
        array[x] = new float*[yDim];
        for(int y=0; y<yDim; y++){
            array[x][y] = new float[zDim];
            for(int z=0; z<zDim; z++){
                result_file >> array[x][y][z];
            }
        }
    }
    result_file.close();
    return array;
}


/*
    draws rectangle around images identified inside camera frame
*/
void draw_bounds(cv::Mat &cameraFrame, std::vector<Prediction> predictions) {
    // draw rectangle on camera frame
    for (std::vector<Prediction>::size_type i = 0; i < predictions.size(); i++) {
        cv::Scalar color(i%3 == 0 ? 255 : 0, i%3 == 1 ? 255 : 0, i%3 == 2 ? 255 : 0);
        float x = std::max(predictions[i].box.x, 0.0f);
        float y = std::max(predictions[i].box.y, 0.0f);
        float w = predictions[i].box.width;
        float h = predictions[i].box.height;
        cv::rectangle(cameraFrame, CvRect(x, y, w, h), color, 2);

        cv::putText(cameraFrame, labels[predictions[i].classIndex], cv::Point(x, y), CV_FONT_HERSHEY_DUPLEX, 0.7, color);
    }
}


// int main() {

//     float ***features = readResults();

//     std::vector<Prediction> predictions = interpretNetworkOutput(features);


//     cv::Mat cameraFrame(416,416, CV_8UC3, cv::Scalar(0, 0, 0));
//     draw_bounds(cameraFrame, predictions);
//     cv::imshow("output", cameraFrame);

//     cv::waitKey(0);
//     for (std::vector<Prediction>::size_type i = 0; i <predictions.size(); i++) {
//         float x = std::max(predictions[i].box.x, 0.0f);
//         float y = std::max(predictions[i].box.y, 0.0f);
//         float w = predictions[i].box.width;
//         float h = predictions[i].box.height;
//         int xmin = x;
//         int xmax = x+w;
//         int ymin = y;
//         int ymax = y+h;
//         printf("class: %s, score: %f, Box: { xmin:%d, ymin: %d, xmax:%d, ymax: %d }\n", labels[predictions[i].classIndex].c_str(), predictions[i].score, xmin, ymin, xmax, ymax);

//     }
// }

