clear;
clc;
caffe.set_mode_cpu();

%%
model = './caffe/tiny-yolo-voc-nobn.prototxt';
weights = './caffe/tiny-yolo-voc-nobn.caffemodel';

net = caffe.Net(model, weights, 'test');

% netparams = {{net.params('conv1',1).get_data(),net.params('conv1',2).get_data()}, ...
% 			{net.params('conv2',1).get_data(),net.params('conv2',2).get_data()}, ...
% 			{net.params('conv3',1).get_data(),net.params('conv3',2).get_data()}, ...
% 			{net.params('conv4',1).get_data(),net.params('conv4',2).get_data()}, ...
% 			{net.params('conv5',1).get_data(),net.params('conv5',2).get_data()}, ...
% 			{net.params('conv6',1).get_data(),net.params('conv6',2).get_data()}, ...
% 			{net.params('conv7',1).get_data(),net.params('conv7',2).get_data()}, ...
%             {net.params('conv8',1).get_data(),net.params('conv8',2).get_data()}, ...
%             {net.params('conv9',1).get_data(),net.params('conv9',2).get_data()}};

netparams = {{net.params('layer1-conv',1).get_data(),net.params('layer1-conv',2).get_data()}, ...
			{net.params('layer3-conv',1).get_data(),net.params('layer3-conv',2).get_data()}, ...
			{net.params('layer5-conv',1).get_data(),net.params('layer5-conv',2).get_data()}, ...
			{net.params('layer7-conv',1).get_data(),net.params('layer7-conv',2).get_data()}, ...
			{net.params('layer9-conv',1).get_data(),net.params('layer9-conv',2).get_data()}, ...
			{net.params('layer11-conv',1).get_data(),net.params('layer11-conv',2).get_data()}, ...
			{net.params('layer13-conv',1).get_data(),net.params('layer13-conv',2).get_data()}, ...
            {net.params('layer14-conv',1).get_data(),net.params('layer14-conv',2).get_data()}, ...
            {net.params('layer15-conv',1).get_data(),net.params('layer15-conv',2).get_data()}};

        
%% 
WeightWidth    = [ 8;  8;  8;  8;  8;  8;  8;  8; 8];
WeightFrac     = [ 4;  10;  9;  10;  11;  11;  10;  14; 11];

MathType   = fimath('RoundingMethod', 'Nearest', 'OverflowAction', 'Saturate', 'ProductMode', 'FullPrecision', 'SumMode', 'FullPrecision');

for i=1:9
	WeightType{i}  = numerictype('Signed',1, 'WordLength', WeightWidth(i), 'FractionLength', WeightFrac(i));
	weight{i}  = fi(netparams{i}{1}, WeightType{i}, MathType);
	bias{i}    = fi(netparams{i}{2}, WeightType{i}, MathType);
end


%%

fid = fopen('weights.dat', 'w');
for i=1:9
    fwrite(fid, storedInteger(weight{i}), 'int8');
    fwrite(fid, storedInteger(bias{i}), 'int8');
end
fclose(fid);

%%
for j=1:9
    a{j} = abs(netparams{j}{1});
    a{j} = a{j}(:);
    a{j} = sort(a{j});
    w{j} = a{j}(floor(length(a{j}) * 0.95),1);
    fi(w{j},1, 8)
end

%%
list = [0.7137255, 7.6881866, 2.298757, 3.4270577, 6.525853, 2.0557456, 2.547694, 5.2614956, 1.9306443, 2.8374465, 5.329569, 1.1087949, 2.0124393, 4.9843855, 0.717907, 1.3517387, 4.687367, 0.54389256, 0.5438, 6.169411874, 4.8567, 2.612, 1.406, 4.1136];
list2 = [-7705, 726, -400, -1353, -10194, -1941, 92, 1767, 0];

for n = 1:length(list2)
    a = fi(list2(n), 1, 8);  
    disp(n); disp(a);
end

%%

% dog2 = dog / 255;

for i = 1:length(dog2)
   dog2(i) = storedInteger(fi(dog2(i),1, 8, 8));
   disp(i);
end
