close all;
clear all;

%%%% DEFINE ALL PATHS

%% Generate tree of paths from the repo's root
path_to_main_code = ...;
addpath(genpath(path_to_main_code));

%% Path to save all intermediate results
saveFolder = ...;
mkClrDir(saveFolder); %% WARNING, ALL FILES IN THE FOLDER WILL BE DELETED IF IT IS NOT EMPTY

% Check that the code has been loaded correctly
if(isempty(which('MovieData')))
    error('The code folder must be loaded first.');
end

% Path to segmented data. Each frame should be in a separate tif.
% I labelled mine "label-frame-000.tif, label-frame-001.tif,..."
fullpath = ...;

%%%% END OF PATHS DEFINITION


% Start parallel pool for parallel computing
try
    parpool(8)
catch 
    disp('Parallel pool running');
end


%% Build Movie Data (MD) object
analysisRoot = ['/tmp/utrack_jules/test_myfiles']; % Output folder for movie metadata and results
mkClrDir(analysisRoot);




c1 = Channel(fullpath);
MD = MovieData(c1,analysisRoot); 
MD.setPath(analysisRoot); 
MD.setFilename('movieData.mat');

MD.pixelSize_ = ...; % Anisotropy in X/Y
MD.pixelSizeZ_ = ...; % Anisotropy in Z
MD.timeInterval_ = ...; % Time between frames
MD.sanityCheck;
MD.save;

%% Detection parameterization and processing
d = Detections(); % Build detection object

% Detect objects using previously segmented data
% /!\ APPARENTLY ONLY ACCEPT DATA IN 16BYTES FORMAT
d = d.buildFromSegmentedMD(MD,1);
processDetection = d.saveInProcess(MD,'detection',1);

MD.addProcess(processDetection);
processDetection.setProcessTag('detection');




% Tracking parameterization and processing 
processTrack=TrackingProcess(MD); % Build tracking object
MD.addProcess(processTrack);    
funParams = processTrack.funParams_;
newFunParams=AP2TrackingParameters(funParams); % Tracking parameters



%% Most important/impactful tracking parameters
newFunParams.gapCloseParam.timeWindow = 1; %IMPORTANT maximum allowed time gap (in frames) between a track segment end and a track segment start that allows linking them.
newFunParams.gapCloseParam.mergeSplit = 0; % (SORT OF FLAG: 4 options for user) 1 if merging and splitting are to be considered, 2 if only merging is to be considered, 3 if only splitting is to be considered, 0 if no merging or splitting are to be considered.
newFunParams.gapCloseParam.minTrackLen = 2; %minimum length of track segments from linking to be used in gap closing.

newFunParams.costMatrices(1).parameters.linearMotion = 1; % use linear motion Kalman filter.
newFunParams.costMatrices(1).parameters.minSearchRadius = 5; %minimum allowed search radius. The search radius is calculated on the spot in the code given a feature's motion parameters. If it happens to be smaller than this minimum, it will be increased to the minimum.
newFunParams.costMatrices(1).parameters.maxSearchRadius = 15; %IMPORTANT maximum allowed search radius. Again, if a feature's calculated search radius is larger than this maximum, it will be reduced to this maximum.
newFunParams.costMatrices(1).parameters.brownStdMult = 3; %multiplication factor to calculate search radius from standard deviation.
newFunParams.costMatrices(1).parameters.useLocalDensity = 1; %1 if you want to expand the search radius of isolated features in the linking (initial tracking) step.

newFunParams.costMatrices(2).parameters.linearMotion = 0; %use linear motion Kalman filter.
newFunParams.costMatrices(2).parameters.minSearchRadius = 1; %minimum allowed search radius.
newFunParams.costMatrices(2).parameters.maxSearchRadius = 10; %maximum allowed search
                                                          %radius.
newFunParams.ChannelIndex=1;

newFunParams.costMatrices(2).parameters.brownStdMult = 3* ...
    ones(newFunParams.gapCloseParam.timeWindow,1); %multiplication factor to calculate Brownian search radius from standard deviation.

newFunParams.EstimateTrackability = true; % IMPORTANT: this param is optional, changing to false can improve computation time significantly

processTrack.setPara(newFunParams);

paramsIn.ChannelIndex=1;
paramsIn.DetProcessIndex=processDetection.getIndex();


%% Run tracker
processTrack.run(paramsIn);

processTrack.setProcessTag('tracking');


%% Extract tracks and trackability data and dump them to .json 
tracks = TracksHandle(processTrack.loadChannelOutput(1)); 


%% Save results as JSON
encoded = jsonencode(tracks);

fid = fopen(strcat(saveFolder,'tracks.json'),'w');
fprintf(fid,'%s',encoded);
fclose(fid); 


