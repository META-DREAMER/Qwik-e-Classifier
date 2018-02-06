#include "cv2.h"
#include "time.h"

typedef struct {
    float x;
    float y;
    float width;
    float height;
} BoundingBox;

typedef struct {
    char* label;
    float confidence;
    BoundingBox bounds;
} Prediction;


int main()
{   
    while (1) {
        capture = cv2.VideoCapture(0);
        frame = capture.read();
        predicition = yolo.get_prediction(frame);
        draw_bounds_with_label(frame, predicition);
    }

}

void draw_bounds_with_label(Frame frame, Prediction predicition) {
        cv2.drawRect(frame, predicition.bounds.x, predicition.bounds.y, predicition.bounds.width, predicition.bounds.height);
        cv2.drawText(frame, predicition.label);
        cv2.imshow("frame", frame);
}
