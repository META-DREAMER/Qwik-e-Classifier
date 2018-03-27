caffe.set_mode_cpu();

model = './caffe/tiny-yolo-nobn.prototxt';
weights = './caffe/tiny-yolo-nobn.caffemodel';

net = caffe.Net(model, weights, 'test');
netparams = {{net.params('conv1',1).get_data(),net.params('conv1',2).get_data()}, ...
			{net.params('conv2',1).get_data(),net.params('conv2',2).get_data()}, ...
			{net.params('conv3',1).get_data(),net.params('conv3',2).get_data()}, ...
			{net.params('conv4',1).get_data(),net.params('conv4',2).get_data()}, ...
			{net.params('conv5',1).get_data(),net.params('conv5',2).get_data()}, ...
			{net.params('conv6',1).get_data(),net.params('conv6',2).get_data()}, ...
			{net.params('conv7',1).get_data(),net.params('conv7',2).get_data()}, ...
            {net.params('conv8',1).get_data(),net.params('conv8',2).get_data()}, ...
            {net.params('conv9',1).get_data(),net.params('conv9',2).get_data()}};

        
%% 
WeightWidth    = [ 8;  8;  8;  8;  8;  8;  8;  8; 8];
WeightFrac     = [ 8;  8;  8;  8;  8;  8;  8;  8; 8];

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