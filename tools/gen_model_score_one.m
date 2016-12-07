
config;

postfix = '_s';

proto_dir     = './models/%s%s/';
proto_dir     = sprintf(proto_dir, model_name, postfix);
proto_file_tr = '%strain.prototxt';
proto_file_ts = '%stest.prototxt';
proto_file_tr = sprintf(proto_file_tr, proto_dir);
proto_file_ts = sprintf(proto_file_ts, proto_dir);
makedir(proto_dir);

flag_indent = true;

anno = load(anno_file);

% get object list
det_file = './cache/det_base_caffenet/train2015/HICO_train2015_00000001.mat';
assert(exist(det_file,'file') ~= 0);
ld = load(det_file);
list_coco_obj = cellfun(@(x)strrep(x,' ','_'),ld.cls,'UniformOutput',false);
list_coco_obj = list_coco_obj(2:end)';

C = {};

% input
if use_pairwise
    src_file = './experiments/templates/train.prototxt.01.input.ho.p.so';
else
    src_file = './experiments/templates/train.prototxt.01.input.ho.so';
end
S = read_file_lines(src_file, flag_indent);
C = [C; S];

% vo classification
src_file = './experiments/templates/train.prototxt.02.vo.%s';
src_file = sprintf(src_file, model_name);
S = read_file_lines(src_file, flag_indent);
C = [C; S];

% o classification
% classfiers
src_file = './experiments/templates/train.prototxt.03.o.classify';
S = read_file_lines(src_file, flag_indent);
S = cellfun(@(x)strrep(x,'${NUM_OUTPUT}',num2str(numel(list_coco_obj),'%d')), S, 'UniformOutput', false);
C = [C; S];
% slice
src_file = './experiments/templates/train.prototxt.03.o.slice';
S = read_file_lines(src_file, flag_indent);
C_TOP = [];
C_PARAM = [];
for i = 1:numel(list_coco_obj)
    line = sprintf('  top: "cls_score_o_%02d_%s"',i,list_coco_obj{i});
    C_TOP = [C_TOP; {line}];  %#ok
    if i ~= numel(list_coco_obj)
        line = sprintf('    slice_point: %d',i);
        C_PARAM = [C_PARAM; {line}];  %#ok
    end
end
ind = cell_find_string(S,'${TOP}');
S = [S(1:ind-1); C_TOP; S(ind+1:end)];
ind = cell_find_string(S,'${PARAM}');
S = [S(1:ind-1); C_PARAM; S(ind+1:end)];
C = [C; S];
% concat
src_file = './experiments/templates/train.prototxt.03.o.concat';
S = read_file_lines(src_file, flag_indent);
ind = cell_find_string(S,'${BOTTOM}');
C_BOTTOM = [];
for i = 1:numel(anno.list_action)
    obj_id = cell_find_string(list_coco_obj, anno.list_action(i).nname);
    obj_name = anno.list_action(i).nname;
    line = sprintf('  bottom: "cls_score_o_%02d_%s"', obj_id, obj_name);
    C_BOTTOM = [C_BOTTOM; {line}];  %#ok
end
S = [S(1:ind-1); C_BOTTOM; S(ind+1:end)];
C = [C; S];

% combine classification
src_file = './experiments/templates/train.prototxt.04.output';
S = read_file_lines(src_file, flag_indent);
ind = cell_find_string(S,'${BOTTOM}');
C_BOTTOM = {'  bottom: "cls_score_vo"'};
C_BOTTOM = [C_BOTTOM; {'  bottom: "cls_score_o"'}];
S = [S(1:ind-1); C_BOTTOM; S(ind+1:end)];
C = [C; S];

% empty line at the end
C = [C; {''}];

% write to file
if ~exist(proto_file_tr, 'file')
    write_file_lines(proto_file_tr, C);
end


% find start line ind
for ind = 1:numel(C)
    if C{ind} == '}'
        break
    end 
end
rm_id = (1:ind)';

% find lines to be removed
for i = ind:numel(C)
    if strcmp(C{i},'  param {') == 1
        rm_id = [rm_id; (i:i+3)'];  %#ok
    end
    if strcmp(C{i},'    weight_filler {') == 1
        rm_id = [rm_id; (i:i+3)'];  %#ok
    end
    if strcmp(C{i},'    bias_filler {') == 1
        rm_id = [rm_id; (i:i+3)'];  %#ok
    end
    if numel(C{i}) >= 14 && strcmp(C{i}(1:14), '  name: "drop7') == 1
        rm_id = [rm_id; (i-1:i+7)'];  %#ok
    end
    if numel(C{i}) >= 18 && strcmp(C{i}(1:18), '  name: "loss_cls"') == 1
        rm_id = [rm_id; (i-1:i+6)'];  %#ok
    end
end

% remove lines and add starting and ending block
C(rm_id) = [];
C_start = {'name: "CaffeNet"'};
C_start = [C_start; ...
    {'input: "data_h"'}; ...
    {'input_shape {'}; ...
    {'  dim: 1'}; ...
    {'  dim: 3'}; ...
    {'  dim: 227'}; ...
    {'  dim: 227'}; ...
    {'}'}];
C_start = [C_start; ...
    {'input: "data_o"'}; ...
    {'input_shape {'}; ...
    {'  dim: 1'}; ...
    {'  dim: 3'}; ...
    {'  dim: 227'}; ...
    {'  dim: 227'}; ...
    {'}'}];
if use_pairwise
    C_start = [C_start; ...
        {'input: "data_p"'}; ...
        {'input_shape {'}; ...
        {'  dim: 1'}; ...
        {'  dim: 2'}; ...
        {'  dim: 64'}; ...
        {'  dim: 64'}; ...
        {'}'}];
end
C_start = [C_start; ...
    {'input: "score_o"'}; ...
    {'input_shape {'}; ...
    {'  dim: 1'}; ...
    {'  dim: 1'}; ...
    {'}'}];

C_end = [{'layer {'}; ...
    {'  name: "cls_prob"'}; ...
    {'  type: "Sigmoid"'}; ...
    {'  bottom: "cls_score"'}; ...
    {'  top: "cls_prob"'}; ...
    {'}'}];

C = [C_start; C; C_end];

% write to file
if ~exist(proto_file_ts, 'file')
    write_file_lines(proto_file_ts, C);
end