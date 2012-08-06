--from bot.lua
function move_all_the_way()
   local b=kinect.getDepth()
   c=b:narrow(3,margin,window) --extracts a strip from the middle of the depth image
   local min = torch.min(c)

   local distance = get_distance(min)
   --print("Distance estimated:",distance)


   while(distance >= (min_obj_dist+min_move_dist)) do
       local distance_to_move = distance - min_obj_dist
       local full_path = path..distance_to_move.." 0"
       os.execute(command_path..full_path)

       b=kinect.getDepth()
       c=b:narrow(3,margin,window)
       min = torch.min(c)
       distance = get_distance(min)
       --print("Distance estimated:",distance)
   end
end


--from findf
function new_median(_x, _y)
	--NOTE: for even frame_counts, it takes the value jus
	nil_count = 0
	turn_count = 0
	if _x >= 320 then
		left_right = -1
   else
		left_right = 1
		playBeep(2)
	end

	shift_xy_tensor(xy_array, _x, _y)
	num_frames = num_frames + 1 --adds to the tally
	if num_frames < frame_count then	--frames aren't full	
		return false --not yet 

	else --frames are full
		num_frames = frame_count --caps the num_frames, since shift removes a frame as well
		
		local sorted_array = torch.sort(xy_array,2)
		return true, sorted_array[1][mid_indx], sorted_array[2][mid_indx]
	end
end

function shift_xy_tensor(_tensor, _x, _y)
	--shifts values left, adding _x,_y to the end
	local len = _tensor:size(2) --length of tensor
	for i=1,len-1 do
		_tensor[1][i] = _tensor[1][i+1] --shift Xs
		_tensor[2][i] = _tensor[2][i+1] --shift Ys
	end
	--add new xy	
	_tensor[1][len] = _x
	_tensor[2][len] = _y
	return _tensor
end

function bot.move_straight()
	--edges the robot forward
	--returns distance traveled
--[[
	local b=kinect.getDepth()
   local c=b:narrow(3,margin,window) --extracts a strip from the middle of the depth image
   local min = torch.min(c)
   local distance = bot.get_distance(min)
   --print("Distance estimated:",distance) --]]
   local depth=source.depthFrame:narrow(3,margin,window)
   local min = torch.min(depth)
   local distance = get_distance(min)

	if (distance >= (min_obj_dist+min_move_dist)) then --too far
		local dist_to_move = distance - min_obj_dist
		--executes movement command
		local full_path = path..dist_to_move.." 0"
      os.execute(command_path..full_path)

	elseif (distance < max_obj_dist-min_move_dist) then --too close
		local dist_to_move = distance - max_obj_dist
		--executes movement command
		local full_path = path..dist_to_move.." 0"
		print("Backing up", dist_to_move)
      os.execute(command_path..full_path)
	end
	
		
end

function bot.move_all_the_way()
   local depth=source.depthFrame:narrow(3,margin,window)
   local min = torch.min(depth)
	local distance = bot.get_distance(min)
   --print("Distance estimated:",distance)


   while(distance >= (min_obj_dist+min_move_dist)) do
       local distance_to_move = distance - min_obj_dist
       local full_path = path..distance_to_move.." 0"
       os.execute(command_path..full_path)

       kinectDepth=kinect.getDepth()
       depth=kinectDepth:narrow(3,margin,window)
       min = torch.min(depth)
       distance = get_distance(min)
       --print("Distance estimated:",distance)
   end
end
