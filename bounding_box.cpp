/*
    file: bounding_box.cpp
    author: Ali Mirza

    This script is part of post-processing module.
    Its responsible for drawing bounding boxes around predictions made by CNN

*/

#include <iostream>
#include <opencv2/opencv.hpp>

// max number of predictions that need to be classified
#define MAX_PREDICTIONS 1

/* data model for bounding boxes */
typedef struct BoundingBox{
    float x;
    float y;
    float width;
    float height;
} BoundingBox;

/* data model for predictions */
typedef struct Prediction{
    char* label;
    float confidence;
    BoundingBox bounds;
} Prediction;

/*
    draws rectangle around images identified inside camera frame
*/
void draw_bounds(cv::Mat &cameraFrame, std::vector<Prediction> predictions) {
    std::vector<cv::Rect> objects;

    // create CvRect for all predicitons
    for (size_t i = 0; i < predictions.size(); i++) {
        objects.push_back(CvRect::CvRect(predictions[i].bounds.x,
                                         predictions[i].bounds.y,
                                         predictions[i].bounds.width,
                                         predictions[i].bounds.height));
    }

    // draw rectangle on camera frame
    for (size_t i = 0; i < objects.size(); i++)
      cv::rectangle(cameraFrame, objects[i], cv::Scalar(255, 0, 0), 5);
}

/*
    get_predictions populates predictions array with objects identified inside image
    note: currently supports mock predictions for testing only
*/
void get_predictions(std::vector<Prediction> &predictions) {
    int i;
    struct Prediction prediction;

    strcpy(prediction.label, "Person");
    prediction.confidence = 50.5;

    prediction.bounds.x = 50 + prediction.bounds.x;
    prediction.bounds.y = 50;
    prediction.bounds.width = 50;
    prediction.bounds.height = 50;

    for (i = 0; i < MAX_PREDICTIONS; i++) {
        predictions.push_back(prediction);
    }
}

int main(void) {
    // prediction objects array
    std::vector<Prediction> predictionObjects;
    
    // capture stream from camera
    cv::VideoCapture capture(0);

    // check if camera stream is available
    if(!capture.isOpened()) {
        std::cout << "Failed to open camera stream" << std::endl;
        return -1;
    }

    while (true) {
        cv::Mat cameraFrame;

        capture.read(cameraFrame);
        
        get_predictions(predictionObjects);

        draw_bounds(cameraFrame,predictionObjects);
        
        cv::imshow("output", cameraFrame);

        if (cv::waitKey(50) >= 0)
            break;
    }

    return 0;
}
