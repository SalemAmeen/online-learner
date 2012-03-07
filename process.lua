-- C coroutines
local c = require 'coroutines'

-- report results
globs = {}
-- stores the position and bounds of tracked objects
globs.results = {}
-- stores an image patch and its associated dense features (prototype)
globs.memory = {}

-- some options
local downs = options.downsampling
local boxh = options.boxh
local boxw = options.boxw

-- camera source, rescaler, color space
if options.source == 'camera' then
   require 'camera'
   source = image.Camera{}
end
rgb2yuv = nn.SpatialColorTransform('rgb2yuv')
rescaler = nn.SpatialReSampling{owidth=options.width/options.downsampling+3,
                                oheight=options.height/options.downsampling+3}

-- encoder
print('loading encoder:')
encoder = torch.load(options.encoder)
encoder:float()
xprint(encoder.modules)
print('')
print('calibrating encoder so as to produce a single vector for a training patch of width ' .. boxw/downs .. ' and height ' .. boxh/downs .. '...')
local t = torch.Tensor(3,boxh/downs,boxw/downs)
local res = encoder:forward(t)
local pw = res:size(3)
encoderm = encoder:clone()
maxpooler = nn.SpatialMaxPooling(pw,pw,1,1)
encoderm:add(maxpooler)
print(' ... appending a ' .. pw .. 'x' .. pw .. ' max-pooling module')
encoder_dw = 1
for i,mod in ipairs(encoderm.modules) do
   if mod.dW then encoder_dw = encoder_dw * mod.dW end
end
print(' ... global downsampling ratio = ' .. encoder_dw)
print('')

-- create other encoders for online learning and full scene encoding
encoder_full = encoderm:clone()
encoder_patch = encoderm:clone()

-- run on neuFlow ?
if options.target == 'neuflow' then
   encoder_full = require 'compile-neuflow'
end

-- grab camera frames, and process them
local function process (ui)
   -- profile loop
   profiler:start('full-loop','fps')

   ------------------------------------------------------------
   -- clear memory / save / load session
   ------------------------------------------------------------
   if ui.forget then
      ui.logit('clearing memory')
      globs.memory = {}
      globs.results = {}
      ui.forget = false
   end
   if ui.save then
      local filen = 'scratch/' .. options.file
      ui.logit('saving memory to ' .. filen)
      local file = torch.DiskFile(filen,'w')
      file:writeObject(globs.memory)
      file:close()
      ui.save = false
   end
   if ui.load then
      local filen = 'scratch/' .. options.file
      ui.logit('reloading memory from ' .. filen)
      local file = torch.DiskFile(filen)
      local loaded = file:readObject()
      globs.memory = loaded
      file:close()
      ui.load = false
   end

   ------------------------------------------------------------
   -- (0) grab frame, get Y chanel and resize
   ------------------------------------------------------------
   profiler:start('get-camera-frame')
   -- store previous frame
   ui.rawFrameP = ui.rawFrameP or torch.Tensor()
   if ui.rawFrame then ui.rawFrameP:resizeAs(ui.rawFrame):copy(ui.rawFrame) end

   -- capture next frame
   ui.rawFrame = source:forward()
   ui.rawFrame = ui.rawFrame:float()

   -- global linear normalization of input frame
   ui.rawFrame:add(-ui.rawFrame:min()):div(math.max(ui.rawFrame:max(),1e-6))

   -- convert and rescale
   ui.yuvFrame = rgb2yuv:forward(ui.rawFrame)
   --ui.yFrame = ui.yuvFrame:narrow(1,1,1)
   ui.procFrame = rescaler:forward(ui.yuvFrame)

   profiler:lap('get-camera-frame')

   ------------------------------------------------------------
   -- (1) track objects
   ------------------------------------------------------------
   if ui.rawFrameP then
      profiler:start('track-interest-points')
      -- store prev results, and prev frame
      globs.results_prev = globs.results
      globs.results = {}

      -- track features for each bounding box
      for i,result in ipairs(globs.results_prev) do
         -- new result:
         local nresult = {class=result.class, id=result.id}

         -- get box around result
         local box = ui.rawFrameP:narrow(3,result.lx,result.w):narrow(2,result.ty,result.h)

         -- track points
         nresult.trackPointsP = opencv.GoodFeaturesToTrack{image=box, count=100}
         nresult.trackPointsP:narrow(2,1,1):add(result.lx-1)
         nresult.trackPointsP:narrow(2,2,1):add(result.ty-1)
         -- track using Pyramidal Lucas Kanade
         nresult.trackPoints = opencv.TrackPyrLK{pair={ui.rawFrameP,ui.rawFrame}, 
                                                 points_in=nresult.trackPointsP}
         local nbpoints = nresult.trackPointsP:size(1)

         -- estimate median flow
         local flows = torch.Tensor(nbpoints, 2)
         flows:narrow(2,1,1):copy(nresult.trackPoints:narrow(2,1,1)):add(-nresult.trackPointsP:narrow(2,1,1))
         flows:narrow(2,2,1):copy(nresult.trackPoints:narrow(2,2,1)):add(-nresult.trackPointsP:narrow(2,2,1))
         flows:narrow(2,1,1):copy( torch.sort(flows:narrow(2,1,1)) )
         flows:narrow(2,2,1):copy( torch.sort(flows:narrow(2,2,1)) )
         local flow_x = flows[math.ceil(nbpoints/2)][1]
         local flow_y = flows[math.ceil(nbpoints/2)][2]

         -- update new result: new center position
         nresult.cx = result.cx + flow_x
         nresult.cy = result.cy + flow_y

         -- estimate spread of previous and new points
         -- previous
         local std = torch.Tensor(nbpoints, 2):copy(nresult.trackPointsP)
         local std_x = math.sqrt( std:narrow(2,1,1):add(-result.cx):pow(2):sum() / nbpoints )
         local std_y = math.sqrt( std:narrow(2,2,1):add(-result.cy):pow(2):sum() / nbpoints )
         -- new
         std:copy(nresult.trackPoints)
         local stdn_x = math.sqrt( std:narrow(2,1,1):add(-nresult.cx):pow(2):sum() / nbpoints )
         local stdn_y = math.sqrt( std:narrow(2,2,1):add(-nresult.cy):pow(2):sum() / nbpoints )

         -- update new result:
         -- new width and height
         local change_x = stdn_x / std_x
         local change_y = stdn_y / std_y
         nresult.w = result.w * change_x
         nresult.h = result.h * change_y
         -- new top, left position
         nresult.lx = nresult.cx - nresult.w/2
         nresult.ty = nresult.cy - nresult.h/2

         -- if result still in the fov, and didnt change too much, then keep it !
         if nresult.ty >= 1 and (nresult.ty+nresult.h-1) <= ui.yuvFrame:size(2)
             and nresult.lx >= 1 and (nresult.lx+nresult.w-1) <= ui.yuvFrame:size(3)
             and change_x < 1.3 and change_x > 0.7 and change_y < 1.3 and change_y > 0.7 
             and flow_x < 100 and flow_y < 100 then
            table.insert(globs.results, nresult)
         else
           print('dropping tracked result:')
           print('change_x = ' .. change_x)
           print('change_y = ' .. change_y)
           print('flow_x = ' .. flow_x)
           print('flow_y = ' .. flow_y)
           print('')
         end
      end
      profiler:lap('track-interest-points')
   end

   ------------------------------------------------------------
   -- (2) perform full detection/recognition
   ------------------------------------------------------------
   profiler:start('encode-full-scene')
   local denseFeatures = encoder_full:forward(ui.procFrame)
   profiler:lap('encode-full-scene')

   ------------------------------------------------------------
   -- (3) estimate class distributions
   ------------------------------------------------------------
   profiler:start('estimate-distributions')
   globs.distributions = globs.distributions or torch.Tensor()
   globs.distributions:resize(#ui.classes+1, denseFeatures:size(2), denseFeatures:size(3)):zero()
   -- fill last class (background) with threshold value
   globs.distributions[#ui.classes+1]:fill(ui.threshold)
   local nfeatures = denseFeatures:size(1)
   for id = 1,#ui.classes do
      if globs.memory[id] then
         -- estimate similarity of all protos with dense features
         for _,proto in ipairs(globs.memory[id]) do
            c.match(denseFeatures, proto.code, globs.distributions[id])
         end
      end
   end
   -- get max (winning category)
   _, globs.winners = torch.max(globs.distributions,1)
   globs.winners = globs.winners[1]
   -- get connected components
   local graph = imgraph.graph(globs.winners:type('torch.FloatTensor'), 4)
   local components = imgraph.connectcomponents(graph, 0.5)
   -- find bounding boxes of blobs
   globs.blobs = c.getblobs(components, globs.winners, #ui.classes+1)
   --
   profiler:lap('estimate-distributions')

   ------------------------------------------------------------
   -- (4) recognize previously learned objects, if they were 
   -- not tracked properly 
   -- (e.g. disappeared then came back...)
   ------------------------------------------------------------
   profiler:start('recognize')
   local off_x = math.floor((ui.rawFrame:size(3) - globs.winners:size(2)*downs*encoder_dw)/2)
   local off_y = math.floor((ui.rawFrame:size(2) - globs.winners:size(1)*downs*encoder_dw)/2)
   for i,blob in pairs(globs.blobs) do
      -- calculate blob center
      local x = math.ceil((blob[1]+blob[2])/2)
      local y = math.ceil((blob[3]+blob[4])/2)
      local id = blob[5]
      if id <= #ui.classes then
         -- new potential object at this location:
         -- left x
         local lx = (x-1) * downs * encoder_dw + 1 + off_x - boxw/2
         -- top y
         local ty = (y-1) * downs * encoder_dw + 1 + off_y - boxh/2
         -- make sure box is in frame
         lx = math.min(math.max(1,lx),ui.rawFrame:size(3)-boxw+1)
         ty = math.min(math.max(1,ty),ui.rawFrame:size(2)-boxh+1)
         -- make sure it doesnt already exist from the tracker:
         local exists = false
         for _,res in ipairs(globs.results) do
            if (lx+boxw) > res.lx and lx < (res.lx+res.w) and (ty+boxh) > res.ty and ty < (res.ty+res.h) then
               -- clears this object from recognition
               exists = true
            end
         end
         if not exists then
            local nresult = {lx=lx, ty=ty, cx=lx+boxw/2, cy=ty+boxh/2, w=boxw, h=boxh,
                             class=ui.classes[id].text:tostring(), id=id}
            table.insert(globs.results, nresult)
         end
      end
   end
   profiler:lap('recognize')

   ------------------------------------------------------------
   -- (5) automatic learning of the object manifolds
   ------------------------------------------------------------
   profiler:start('auto-learn')
   if ui.activeLearning then
      for _,res in ipairs(globs.results) do
         -- get center prediction
         local cx = (res.cx-off_x-1)/downs/encoder_dw+1
         local cy = (res.cy-off_y-1)/downs/encoder_dw+1
         local recog = globs.distributions[res.id][cy][cx]
         if recog < (ui.threshold*0.9) then
            -- auto learn
            ui.logit('auto-learning [' .. res.class .. ']', ui.colors[res.id])

            -- compute x,y coordinates
            local lx = math.min(math.max(res.cx-boxw/2,0),ui.yuvFrame:size(3)-boxw)
            local ty = math.min(math.max(res.cy-boxh/2,0),ui.yuvFrame:size(2)-boxh)

            -- remap to smaller proc map
            lx = lx / downs + 1
            ty = ty / downs + 1

            -- extract patch at that location
            local patch = ui.procFrame:narrow(3,lx,boxw/downs):narrow(2,ty,boxh/downs):clone()

            -- compute code for patch
            local code = encoder_patch:forward(patch):clone()

            -- store patch and its code
            globs.memory[res.id] = globs.memory[res.id] or {}
            table.insert(globs.memory[res.id], {patch=patch, code=code})
         end
      end
   end
   profiler:lap('auto-learn')

   ------------------------------------------------------------
   -- (6) capture new prototype, upon user request
   ------------------------------------------------------------
   if ui.learn then
      profiler:start('learn-new-view')
      -- compute x,y coordinates
      local lx = math.min(math.max(ui.learn.x-boxw/2,0),ui.yuvFrame:size(3)-boxw)
      local ty = math.min(math.max(ui.learn.y-boxh/2,0),ui.yuvFrame:size(2)-boxh)
      ui.logit('adding [' .. ui.learn.class .. '] at ' .. lx .. ',' .. ty, ui.colors[ui.learn.id])

      -- and create a result !!
      local nresult = {lx=lx, ty=ty, cx=lx+boxw/2, cy=ty+boxh/2, w=boxw, h=boxh,
                       class=ui.classes[ui.learn.id].text:tostring(), id=ui.learn.id}
      table.insert(globs.results, nresult)

      -- remap to smaller proc map
      lx = lx / downs + 1
      ty = ty / downs + 1

      -- extract patch at that location
      local patch = ui.procFrame:narrow(3,lx,boxw/downs):narrow(2,ty,boxh/downs):clone()

      -- compute code for patch
      local code = encoder_patch:forward(patch):clone()

      -- store patch and its code
      globs.memory[ui.learn.id] = globs.memory[ui.learn.id] or {}
      table.insert(globs.memory[ui.learn.id], {patch=patch, code=code})

      -- done
      ui.learn = nil
      profiler:lap('learn-new-view')
   end
end

return process
