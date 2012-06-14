local nil_count = 0; -- counts the number of times no result is generated
local no_object_count = 10; -- constant for how many frames of no object before the robot goes looking around
local turn_count = 0; -- tracks which movement the robot needs to make

local lag = 12 -- the number of frames before the robot continues to turn
local look_deg = 30


local frame_count = 4; -- number of frames to accumulate for median calculation
local mid_indx;
if frame_count % 2 ==0 then
	mid_indx = frame_count/2+1
else
	mid_indx = frame_count/2+.5
end

local array=torch.Tensor(2,frame_count); -- arrays to put in all the values accumulated
local xy_array=torch.Tensor(2,frame_count); 
local num_frames = 0; -- keep track of the number of frames already accumulated

local left_right = -1; -- the object is at the left or right at the most recent frame, 1 means left, -1 means right
function findMedian(_options, _x, _y, _screenW)
--returns the median angle from a 
	
	local cx = _x; local cy = _y;
   if cx == -1 and cy == -1 then -- no result
		nil_count = nil_count + 1;
      if nil_count >= no_object_count then
      	num_frames = 0; --resets the median count
			look_around()
		end

	else --if there is a result
		local isArrayFull, final_x, final_y;
      isArrayFull, final_x, final_y = median(cx,cy);

      if isArrayFull == true then -- calculate the predicted angle once the median has been obtained
										  -- only enters if done accumulating frames
			local dx=final_x-_screenW/2
			local ang_pred_rad = torch.atan(dx/640)--THIS IS THE ZSCREEN VALUE
			local ang_pred_deg = ang_pred_rad * 180 / 3.1415
				
			--printMedian(ang_pred_deg, final_x, final_y)

			return ang_pred_deg
		end	
	end
end



function median(x_coord, y_coord)
   nil_count = 0;
	turn_count = 0; -- reset nil_count and turn_count once the robot has found the object
	if x_coord >= 320 then
		left_right = 1 -- left
   else
		left_right = -1 -- right
	end
	array[1][num_frames+1]=x_coord
	array[2][num_frames+1]=y_coord
	num_frames = num_frames + 1;
	if num_frames == frame_count then
		--Actually calculates the median here
		--TO DO: allow to work with even numbers of frames
		local sorted_array = torch.sort(array,2) -- sort the array in ascending order
		num_frames = 0;
		return true, sorted_array[1][frame_count/2 + 0.5], sorted_array[2][frame_count/2 + 0.5] -- return the median
	else 
		return false
	end
end


function look_around()
	local n = 360/look_deg
	if turn_count % lag == 0 then
		print("Left/right", left_right)
		turn_bot(left_right*look_deg) -- if it's left, then the argument is negative, if it's right, then the argument is positive
		playBeep(1)
	end
	turn_count = turn_count + 1;
	if(turn_count == n*lag) then
		print("I can't find the object")
		turn_count = 0;
		--playBeep(4)
	end
end

function playBeep(beepNum)
	os.execute("/usr/bin/mplayer ~/online-learner/sound/beep-"..beepNum..".wav&")
end

function printMedian(ang_pred_deg, fx, fy)
	print('~~~~~~~FROM MEDIAN~~~~~~~~')
	print('angle [calculated] :', ang_pred_deg,'degrees')
	print('median x:',f_x,' median y:', f_y)
	state.logit('predicted angle='.. ang_pred_deg .. 'degrees at x:' .. fx .. ' y:' .. fy)			
end	

