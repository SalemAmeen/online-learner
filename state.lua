-- global state (excluding ui state)
local state = {}

-- tensors holding raw and processed frames
state.rawFrame = torch.Tensor()
state.rawFrameP = torch.Tensor()
state.procFrame = torch.Tensor()

-- stores the position and bounds of tracked objects
state.results_prev = {}
state.results = {}

-- stores an image patch and its associated dense features (prototype)
state.memory = {}

-- state.distributions[class] holds a matrix of pseudoprobabilities that
-- the corresponding prototype vector in the output space matches the class
-- Tensor of dimension (# of classes, including background) x
--  (height of output space) x (width of output space) 
state.distributions  = torch.Tensor()

-- holds the most probable class for each point in the output space
state.winners = torch.Tensor()

-- holds the bounding boxes for all blobs (connected regions) where the
-- winner is the same, excluding where the winner is the background
state.blobs = {}

state.classes = ui.classes
state.colors = ui.colors
state.threshold = options.recognition_lthreshold
state.autolearn = options.autolearn


if options.nogui then
   ui = nil
   function state.begin()
      while state.frame < source.nframes do
         profiler:start('full-loop','fps')
         process()
         profiler:lap('full-loop')
      end
   end
   function state.logit(msg,color)
      print(msg)
   end
else
   local timer = qt.QTimer()
   local function loop()
      profiler:start('full-loop','fps')
      process()
      display.update()
      profiler:lap('full-loop')
      display.log()
      timer:start()      
   end
   timer.interval = 10
   timer.singleShot = true
   qt.connect(timer,
              'timeout()',
              loop)
   function state.begin()
      timer:start()
   end
   function state.logit(msg,color)
      ui.logit(msg,color)
   end
end

return state
