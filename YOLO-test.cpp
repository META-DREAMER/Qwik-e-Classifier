// Unit tests for YOLO.cpp
// Created by Hammad Jutt, March 3 2018
#include "catch.hpp"
#include "YOLO.hpp"

TEST_CASE( "Sigmoid is computed", "[sigmoid]" ) {
    REQUIRE(sigmoid(1) == Approx(0.731059));
    REQUIRE(sigmoid(0) == Approx(0.5));
    REQUIRE(sigmoid(-1) == Approx(0.268941));
    REQUIRE(sigmoid(100) == Approx(1));
}


TEST_CASE( "Index of largest value in vector is returned", "[argMax]" ) {
    std::vector<double> vec;

    SECTION( "Basic case" ) {
        vec.push_back(1.1);
        vec.push_back(1.3);
        vec.push_back(1.2);
        REQUIRE(argMax(vec) == 1);
    }

    SECTION( "Works with negative numbers" ) {
        vec.push_back(-20);
        vec.push_back(-30);
        vec.push_back(-10);
        REQUIRE(argMax(vec) == 2);
    }

    SECTION( "Works with empty vectors" ) {
        REQUIRE(argMax(vec) == 0);        
    }  
}

TEST_CASE( "Predictions compared based on score", "[comparePredictions]" ) {
    Prediction a = {}; a.score = 0.95;
    Prediction b = {}; b.score = 0.94;
    
    REQUIRE(comparePredictions(a, b) == true);
    
    a.score = 0.93;
    REQUIRE(comparePredictions(a, b) == false);
    
    a.score = 0.94;
    REQUIRE(comparePredictions(a, b) == false);
}

TEST_CASE( "IOU overlap is returned", "[iou]" ) {
    Box a = {};
    Box b = {};

    SECTION( "No overlap" ) {
        a.x = 0; a.y = 0; a.width = 5; a.height = 5;
        b.x = 5; b.y = 5; b.width = 5; b.height = 5;
        REQUIRE(iou(a, b) == 0.0);
    }

    SECTION( "Full overlap" ) {
        a.x = 0; a.y = 0; a.width = 5; a.height = 5;
        b.x = 0; b.y = 0; b.width = 5; b.height = 5;
        REQUIRE(iou(a, b) == 1.0);
    }

    SECTION( "1/4 overlap" ) {
        a.x = 10; a.y = 10; a.width = 10; a.height = 10;
        b.x = 15; b.y = 15; b.width = 10; b.height = 10;
        REQUIRE(iou(a, b) == Approx(0.142857));
    }

    SECTION( "4/5 overlap" ) {
        a.x = 0; a.y = 0; a.width = 5; a.height = 5;
        b.x = 0; b.y = 1; b.width = 5; b.height = 5;
        REQUIRE(iou(a, b) == Approx(2.0/3.0));
    }

    SECTION( "Zero area" ) {
        a.x = 10; a.y = 10; a.width = 0; a.height = 10;
        b.x = 15; b.y = 15; b.width = 10; b.height = 10;
        REQUIRE(iou(a, b) == 0.0);

        a.width = 10; b.width = 0;
        REQUIRE(iou(a, b) == 0.0);
    }
}

TEST_CASE( "Softmax applied to given values", "[softmax]" ) {
    std::vector<double> vec;

    SECTION( "Basic case" ) {
        vec.push_back(-100);
        std::vector<double> expected;
        expected.push_back(1.0);
        REQUIRE_THAT(softmax(vec), Catch::Equals(expected));
    }

    SECTION( "Empty vector" ) {
        REQUIRE_THAT(softmax(vec), Catch::Equals(vec));
    }

    SECTION( "Correct values on each element" ) {
        vec.push_back(10);
        vec.push_back(10);
        vec.push_back(10);
        vec.push_back(10);

        std::vector<double> expected;
        expected.push_back(0.25);
        expected.push_back(0.25);
        expected.push_back(0.25);
        expected.push_back(0.25);

        REQUIRE_THAT(softmax(vec), Catch::Equals(expected));
    }

    SECTION( "Total sum is 1" ) {
        vec.push_back(-1);
        vec.push_back(2);
        vec.push_back(-3);
        vec.push_back(4);

        std::vector<double> res = softmax(vec);
        double sum = 0.0;
        for (auto& n : res)
            sum += n;

        REQUIRE(sum == 1.0);
    }
}

TEST_CASE( "Redundant boxes are filtered", "[filterRedundantBoxes]" ) {
    Box boxA = {}; boxA.x = 0; boxA.y = 0; boxA.width = 5; boxA.height = 5;
    Box boxB = {}; boxB.x = 5; boxB.y = 5; boxB.width = 5; boxB.height = 5;
    Box boxC = {}; boxC.x = 5; boxC.y = 10; boxC.width = 5; boxC.height = 5;
    
    Prediction a = {}; a.score = 0.5; a.box = boxA; a.classIndex = 0;
    Prediction b = {}; b.score = 0.7; b.box = boxB; b.classIndex = 1;
    Prediction c = {}; c.score = 0.3; c.box = boxC; c.classIndex = 2;

    float threshold = 0.5;
    int limit = 10;
    
    SECTION( "Handles empty vectors" ) {
        std::vector<Prediction> preds;
        std::vector<Prediction> res = filterRedundantBoxes(preds, threshold, limit);

        REQUIRE(res.size() == 0);
    }

    SECTION( "Non overlapping boxes sorted but not filtered" ) {
        std::vector<Prediction> preds;
        preds.push_back(a);
        preds.push_back(b);
        preds.push_back(c);
        
        std::vector<Prediction> res = filterRedundantBoxes(preds, threshold, limit);

        REQUIRE(res.size() == 3);
        REQUIRE(res[0].classIndex == b.classIndex);
        REQUIRE(res[1].classIndex == a.classIndex);
        REQUIRE(res[2].classIndex == c.classIndex);   
    }

    SECTION( "Number of boxes does not exceed limit" ) {
        limit = 1;
        std::vector<Prediction> preds;
        preds.push_back(a);
        preds.push_back(b);
        preds.push_back(c);
        
        std::vector<Prediction> res = filterRedundantBoxes(preds, threshold, limit);

        REQUIRE(res.size() == 1);
        REQUIRE(res[0].classIndex == b.classIndex);
    }

    SECTION( "Boxes overlapping with lower score are removed if exceeding threshold" ) {
        boxA.x = 0; boxA.y = 0; boxA.width = 5; boxA.height = 5;
        boxB.x = 0; boxB.y = 1; boxB.width = 5; boxB.height = 5;

        a.box = boxA;
        b.box = boxB;
        c.score = 0.9;

        std::vector<Prediction> preds;
        preds.push_back(a);
        preds.push_back(b);
        preds.push_back(c);
        
        std::vector<Prediction> res = filterRedundantBoxes(preds, threshold, limit);

        REQUIRE(res.size() == 2);
        REQUIRE(res[0].classIndex == c.classIndex);
        REQUIRE(res[1].classIndex == b.classIndex);

        // Increase threshold and test again
        threshold = 0.75;
        res = filterRedundantBoxes(preds, threshold, limit);   
        
        REQUIRE(res.size() == 3);
        REQUIRE(res[0].classIndex == c.classIndex);
        REQUIRE(res[1].classIndex == b.classIndex);
        REQUIRE(res[2].classIndex == a.classIndex);
    }
}
