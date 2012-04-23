-- define tracking algorithms

local function simpletracker(result)
   -- new result:
   local nresult = {class=result.class, id=result.id}

   -- get box around result
   local box = state.rawFrameP:narrow(3,result.lx,result.w):narrow(2,result.ty,result.h)

   -- track points
   nresult.trackPointsP = opencv.GoodFeaturesToTrack{image=box, count=100}
   if nresult.trackPointsP:dim() < 2 then
      return nil
   end
   local nbpoints = nresult.trackPointsP:size(1)
   nresult.trackPointsP:narrow(2,1,1):add(result.lx-1)
   nresult.trackPointsP:narrow(2,2,1):add(result.ty-1)

   -- track using Pyramidal Lucas Kanade
   nresult.trackPoints = opencv.TrackPyrLK{pair={state.rawFrameP,state.rawFrame},
                                           points_in=nresult.trackPointsP}

   -- estimate median flow
   local flows = torch.Tensor(nbpoints, 2)
   flows:narrow(2,1,1):copy(nresult.trackPoints:narrow(2,1,1)):add(-nresult.trackPointsP:narrow(2,1,1))
   flows:narrow(2,2,1):copy(nresult.trackPoints:narrow(2,2,1)):add(-nresult.trackPointsP:narrow(2,2,1))
   flows:narrow(2,1,1):copy( torch.sort(flows:narrow(2,1,1)) )
   flows:narrow(2,2,1):copy( torch.sort(flows:narrow(2,2,1)) )
   nresult.flow_x = flows[math.ceil(nbpoints/2)][1]
   nresult.flow_y = flows[math.ceil(nbpoints/2)][2]

   -- update new result: new center position
   nresult.cx = result.cx + nresult.flow_x
   nresult.cy = result.cy + nresult.flow_y

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
   nresult.change_x = stdn_x / std_x
   nresult.change_y = stdn_y / std_y
   -- check for nan
   if nresult.change_x ~= nresult.change_x then nresult.change_x = 1 end
   if nresult.change_y ~= nresult.change_y then nresult.change_y = 1 end
   nresult.w = result.w * nresult.change_x
   nresult.h = result.h * nresult.change_y
   -- new top, left position
   nresult.lx = nresult.cx - nresult.w/2
   nresult.ty = nresult.cy - nresult.h/2

   return nresult
end

local function fbtracker(result)
   -- new result:
   local nresult = {class=result.class, id=result.id}

   -- track points
   --
   -- put tracking points on grid, every Npx pixels
   local Npx = 5
   if math.min(result.w, result.h) < 2*Npx then return end
   local xpoints = torch.floor(torch.linspace(result.lx-1,result.lx-1+result.w, math.floor(result.w/Npx)))
   local xn = xpoints:size(1)
   local ypoints = torch.floor(torch.linspace(result.ty-1,result.ty-1+result.h, math.floor(result.h/Npx)))
   local yn = ypoints:size(1)
   local allnbpoints = xn * yn
   local nbpoints = math.floor(allnbpoints/2)
   local allTrackPointsP = torch.Tensor(allnbpoints,2)
   for i = 1,xn do
       local xy = allTrackPointsP:narrow(1,1+yn*(i-1),yn)
       local x = xy:narrow(2,1,1)
       local y = xy:narrow(2,2,1)
       x:fill(xpoints[i])
       y:copy(ypoints)
   end
   --
   -- track using Pyramidal Lucas Kanade
   local allTrackPointsF = opencv.TrackPyrLK{pair={state.rawFrameP,state.rawFrame},
                                          points_in=allTrackPointsP}

   local allTrackPointsB = opencv.TrackPyrLK{pair={state.rawFrame,state.rawFrameP},
                                          points_in=allTrackPointsF}

   -- get top 50% with smallest FB error
   local sqdf=allTrackPointsB:mul(-1):add(allTrackPointsP):pow(2)
   local sumsq = torch.sum(sqdf,2):select(2,1)
   local _,idx=torch.sort(sumsq,1)
   --
   nresult.trackPointsP = torch.Tensor(nbpoints,2)
   nresult.trackPoints = torch.Tensor(nbpoints,2)
   for i = 1,nbpoints do
       nresult.trackPointsP[i]:copy(allTrackPointsP[idx[i]])
       nresult.trackPoints[i]:copy(allTrackPointsF[idx[i]])
   end

   -- estimate median flow
   local flows = torch.Tensor(nbpoints, 2)
   flows:narrow(2,1,1):copy(nresult.trackPoints:narrow(2,1,1)):add(-nresult.trackPointsP:narrow(2,1,1))
   flows:narrow(2,2,1):copy(nresult.trackPoints:narrow(2,2,1)):add(-nresult.trackPointsP:narrow(2,2,1))
   flows:narrow(2,1,1):copy( torch.sort(flows:narrow(2,1,1)) )
   flows:narrow(2,2,1):copy( torch.sort(flows:narrow(2,2,1)) )
   nresult.flow_x = flows[math.ceil(nbpoints/2)][1]
   nresult.flow_y = flows[math.ceil(nbpoints/2)][2]

   -- update new result: new center position
   nresult.cx = result.cx + nresult.flow_x
   nresult.cy = result.cy + nresult.flow_y

   -- ratio between current point distance and previous point distance for each pair of points
   local dratio = torch.Tensor(nbpoints*(nbpoints-1)/2, 2)
   local offset = 0
   for i = 1,nbpoints do
       for j = i+1,nbpoints do
           dist=nresult.trackPoints[i]-nresult.trackPoints[j]
           distP=nresult.trackPointsP[i]-nresult.trackPointsP[j]
           dratio[offset+(j-i)]:copy(torch.cdiv(dist,distP))
       end
       offset = offset+(nbpoints-i)
   end
   dratio, _ = torch.sort(dratio,1)
   nresult.change_x = dratio[math.ceil(dratio:size(1)/2)][1]
   nresult.change_y = dratio[math.ceil(dratio:size(1)/2)][2]
   -- check for nan
   if nresult.change_x ~= nresult.change_x then nresult.change_x = 1 end
   if nresult.change_y ~= nresult.change_y then nresult.change_y = 1 end

   -- new width and height
   nresult.w = result.w * nresult.change_x
   nresult.h = result.h * nresult.change_y
   -- new top, left position
   nresult.lx = nresult.cx - nresult.w/2
   nresult.ty = nresult.cy - nresult.h/2

   return nresult
end

-- return selected tracking algorithm
local trackers = { simple = simpletracker, 
                   fb = fbtracker
                 }
local tracker = trackers[options.tracker]

local function trackall()
   -- store prev results, and prev frame
   state.results_prev = state.results
   state.results = {}

   -- track features for each bounding box
   for i,result in ipairs(state.results_prev) do
      local nresult = tracker(result)

      -- if result still in the fov, and didnt change too much, then keep it !
      if not nresult then
         print('dropping tracked result: no tracking points returns\n')
      elseif nresult.ty < 1 or (nresult.ty+nresult.h-1) > state.yuvFrame:size(2)
          or nresult.lx < 1 or (nresult.lx+nresult.w-1) > state.yuvFrame:size(3)
          or nresult.change_x >= options.t_sizechange_uthreshold
          or nresult.change_x <= options.t_sizechange_lthreshold
          or nresult.change_y >= options.t_sizechange_uthreshold
          or nresult.change_y <= options.t_sizechange_lthreshold
          or nresult.flow_x >= options.t_flow_uthreshold
          or nresult.flow_y >= options.t_flow_uthreshold then
         print('dropping tracked result:')
         print('change_x = ' .. nresult.change_x)
         print('change_y = ' .. nresult.change_y)
         print('flow_x = ' .. nresult.flow_x)
         print('flow_y = ' .. nresult.flow_y)
         print('')
      else
         nresult.source = 1
         table.insert(state.results, nresult)
      end
   end
end

local function tracknone()
   state.results = {}
end

if not tracker then
   assert(options.tracker == 'off',
          'invalid tracking algorithm ' .. options.tracker)
   return tracknone 
else
   require 'opencv'
   return trackall
end
