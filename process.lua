-- C coroutines
local c = require 'coroutines'

-- some options
local downs = options.downs
local boxh = options.boxh
local boxw = options.boxw

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
local ph = res:size(2)
encoderm = encoder:clone()
maxpooler = nn.SpatialMaxPooling(pw,ph,1,1)
encoderm:add(maxpooler)
print(' ... appending a ' .. pw .. 'x' .. ph .. ' max-pooling module')
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
local function process()
   ------------------------------------------------------------
   -- (0) grab frame, get Y chanel and resize
   ------------------------------------------------------------
   profiler:start('get-frame')
   source:getframe()
   profiler:lap('get-frame')

   ------------------------------------------------------------
   -- (1) track objects
   ------------------------------------------------------------
   profiler:start('track-interest-points')
   tracker()
   profiler:lap('track-interest-points')

   ------------------------------------------------------------
   -- (2) perform full detection/recognition
   ------------------------------------------------------------
   profiler:start('encode-full-scene')
   local denseFeatures = encoder_full:forward(state.procFrame)
   profiler:lap('encode-full-scene')

   ------------------------------------------------------------
   -- (3) estimate class distributions
   ------------------------------------------------------------
   profiler:start('estimate-distributions')
   state.distributions:resize(#state.classes+1, denseFeatures:size(2), denseFeatures:size(3)):zero()
   -- fill last class (background) with threshold value
   state.distributions[#state.classes+1]:fill(state.threshold)
   local nfeatures = denseFeatures:size(1)
   for id = 1,#state.classes do
      if state.memory[id] then
         -- estimate similarity of all protos with dense features
         for _,proto in ipairs(state.memory[id]) do
            c.match(denseFeatures, proto.code, state.distributions[id])
         end
      end
   end
   -- get max (winning category)
   _, state.winners = torch.max(state.distributions,1)
   state.winners = state.winners[1]
   -- get connected components
   local graph = imgraph.graph(state.winners:type('torch.FloatTensor'), 4)
   local components = imgraph.connectcomponents(graph, 0.5)
   -- find bounding boxes of blobs
   state.blobs = c.getblobs(components, state.winners, #state.classes+1)
   --
   profiler:lap('estimate-distributions')

   ------------------------------------------------------------
   -- (4) recognize previously learned objects, if they were 
   -- not tracked properly 
   -- (e.g. disappeared then came back...)
   ------------------------------------------------------------
   profiler:start('recognize')
   local off_x = math.floor((state.rawFrame:size(3) - state.winners:size(2)*downs*encoder_dw)/2)
   local off_y = math.floor((state.rawFrame:size(2) - state.winners:size(1)*downs*encoder_dw)/2)
   for i,blob in pairs(state.blobs) do
      -- calculate blob center
      local x = math.ceil((blob[1]+blob[2])/2)
      local y = math.ceil((blob[3]+blob[4])/2)
      local id = blob[5]
      if id <= #state.classes then

         -- new potential object at this location:
         -- left x
         local lx = (x-1) * downs * encoder_dw + 1 + off_x - boxw/2
         -- top y
         local ty = (y-1) * downs * encoder_dw + 1 + off_y - boxh/2
         -- make sure box is in frame
         lx = math.min(math.max(1,lx),state.rawFrame:size(3)-boxw+1)
         ty = math.min(math.max(1,ty),state.rawFrame:size(2)-boxh+1)
         -- make sure it doesnt already exist from the tracker:
         local exists = false
         for _,res in ipairs(state.results) do
            if (lx+boxw) > res.lx and lx < (res.lx+res.w) and (ty+boxh) > res.ty and ty < (res.ty+res.h) then
               -- clears this object from recognition
               exists = true
            end
         end
         if not exists then
            local nresult = {lx=lx, ty=ty, cx=lx+boxw/2, cy=ty+boxh/2, w=boxw, h=boxh,
                             class=state.classes[id], id=id}
            table.insert(state.results, nresult)
         end
      end
   end
   profiler:lap('recognize')

   ------------------------------------------------------------
   -- (5) automatic learning of the object manifolds
   ------------------------------------------------------------
   profiler:start('auto-learn')
   if state.autolearn then
      for _,res in ipairs(state.results) do
         -- get center prediction
         local cx = (res.cx-off_x-1)/downs/encoder_dw+1
         local cy = (res.cy-off_y-1)/downs/encoder_dw+1
         local recog = state.distributions[res.id][cy][cx]
         if recog < (state.threshold*0.9) then
            -- auto learn
            state.logit('auto-learning [' .. res.class .. ']',res.id)

            -- compute x,y coordinates
            local lx = math.min(math.max(res.cx-boxw/2,0),state.yuvFrame:size(3)-boxw)
            local ty = math.min(math.max(res.cy-boxh/2,0),state.yuvFrame:size(2)-boxh)

            -- remap to smaller proc map
            lx = lx / downs + 1
            ty = ty / downs + 1

            -- extract patch at that location
            local patch = state.procFrame:narrow(3,lx,boxw/downs):narrow(2,ty,boxh/downs):clone()

            -- compute code for patch
            local code = encoder_patch:forward(patch):clone()

            -- store patch and its code
            state.memory[res.id] = state.memory[res.id] or {}
            table.insert(state.memory[res.id], {patch=patch, code=code})
         end
      end
   end
   profiler:lap('auto-learn')

   ------------------------------------------------------------
   -- (6) capture new prototype, upon user request
   ------------------------------------------------------------
   if state.learn then
      profiler:start('learn-new-view')
      -- compute x,y coordinates
      local lx = math.min(math.max(state.learn.x-boxw/2,0),state.yuvFrame:size(3)-boxw)
      local ty = math.min(math.max(state.learn.y-boxh/2,0),state.yuvFrame:size(2)-boxh)
      state.logit('adding [' .. state.learn.class .. '] at ' .. lx 
                  .. ',' .. ty, state.learn.id)

      -- and create a result !!
      local nresult = {lx=lx, ty=ty, cx=lx+boxw/2, cy=ty+boxh/2, w=boxw, h=boxh,
                       class=state.classes[state.learn.id], id=state.learn.id}
      table.insert(state.results, nresult)

      -- remap to smaller proc map
      lx = lx / downs + 1
      ty = ty / downs + 1

      -- extract patch at that location
      local patch = state.procFrame:narrow(3,lx,boxw/downs):narrow(2,ty,boxh/downs):clone()

      -- compute code for patch
      local code = encoder_patch:forward(patch):clone()

      -- store patch and its code
      state.memory[state.learn.id] = state.memory[state.learn.id] or {}
      table.insert(state.memory[state.learn.id], {patch=patch, code=code})

      -- done
      state.learn = nil
      profiler:lap('learn-new-view')
   end
end

return process
