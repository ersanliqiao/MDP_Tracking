% testing MDP
function MDP_test

is_show = 1;

opt = globals();
seq_idx = 1;
seq_name = opt.mot2d_train_seqs{seq_idx};
seq_num = opt.mot2d_train_nums(seq_idx);
seq_set = 'train';

% build the dres structure for images
dres_image = read_dres_image(opt, seq_set, seq_name, seq_num);
fprintf('read images done\n');

% read detections
filename = fullfile(opt.mot, opt.mot2d, seq_set, seq_name, 'det', 'det.txt');
dres_det = read_mot2dres(filename);

% read ground truth
filename = fullfile(opt.mot, opt.mot2d, seq_set, seq_name, 'gt', 'gt.txt');
dres_gt = read_mot2dres(filename);

% load the trained model
object = load('tracker.mat');
tracker = object.tracker;

% intialize tracker
I = dres_image.I{1};
tracker = MDP_initialize_test(tracker, size(I,2), size(I,1), dres_det);

% for each frame
trackers = [];
id = 0;
for fr = 1:seq_num
    % extract detection
    index = find(dres_det.fr == fr);
    dres = sub(dres_det, index);
    
    % apply existing trackers
    for i = 1:numel(trackers)
        trackers{i} = process(fr, dres_image, dres, trackers{i});
    end
    
    % find detections for initialization
    [index, dres_track] = generate_initial_index(trackers, dres);
    for i = 1:numel(index)
        id = id + 1;
        trackers{end+1} = initialize(fr, dres_image, id, dres, index(i), tracker);
    end
    
    if is_show
        figure(1);
        
        % show ground truth
        subplot(2, 2, 1);
        show_dres(fr, dres_image.I{fr}, 'GT', dres_gt);

        % show detections
        subplot(2, 2, 2);
        show_dres(fr, dres_image.I{fr}, 'Detections', dres_det);        

        % show tracking results
        subplot(2, 2, 3);
        show_dres(fr, dres_image.I{fr}, 'Tracking', dres_track, 2);

        % show lost targets
        subplot(2, 2, 4);
        show_dres(fr, dres_image.I{fr}, 'Lost', dres_track, 3);

        pause();
    end
end

% save results
filename = sprintf('%s/%s.mat', opt.results, seq_name);
save(filename, 'dres_track');

% write tracking results
filename = sprintf('%s/%s.txt', opt.results, seq_name);
fprintf('write results: %s\n', filename);
write_tracking_results(filename, dres_track, opt.tracked);

% evaluation
benchmark_dir = fullfile(opt.mot, opt.mot2d, seq_set, filesep);
evaluateTracking({seq_name}, opt.results, benchmark_dir);


% initialize a tracker
% dres: detections
function tracker = initialize(fr, dres_image, id, dres, ind, tracker)

if tracker.state ~= 1
    return;
else  % active

    % initialize the LK tracker
    tracker = LK_initialize(tracker, fr, id, dres, ind, dres_image);

    tracker = MDP_value(tracker, fr, dres_image, dres, ind);
end


% apply a single tracker
% dres: detections
function tracker = process(fr, dres_image, dres, tracker)

if tracker.state == 0
    return;

% tracked    
elseif tracker.state == 2
    tracker.streak_occluded = 0;
    tracker = MDP_value(tracker, fr, dres_image, dres, []);

% occluded
elseif tracker.state == 3
    tracker.streak_occluded = tracker.streak_occluded + 1;
    % find a set of detections for association
    index_det = generate_association_index(tracker, fr, dres);
    tracker = MDP_value(tracker, fr, dres_image, dres, index_det);

    if tracker.streak_occluded > opt.max_occlusion
        tracker.state = 0;
        fprintf('target %d exits due to long time occlusion\n', tracker.target_id);
    end
end

% check if target outside image
if isempty(find(tracker.flags == 1, 1)) == 1
    if tracker.dres.x(end) < 0 || tracker.dres.x(end)+tracker.dres.w(end) > dres_image.w(fr)
        fprintf('target %d outside image by checking boarders\n', tracker.target_id);
        tracker.state = 0;
    end 
end