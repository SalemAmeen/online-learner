local nil_count = 0; -- counts the number of times no result is generated
local no_object_count = 10; -- constant for how many frames of no object before the robot goes looking around
local move_count = 0; -- tracks which movement the robot needs to make

function findMedian(_options, _x, _y, _screenW)
--returns the median angle from a 
	if _options.findfollow then 
		local cx = _x; local cy = _y;
      if cx == -1 and cy == -1 then -- no result
			nil_count = nil_count + 1;
      	if nil_count >= no_object_count then
            num = 0; --resets the median count
				look_around()
			end

      else --if there is a result
			local finish, final_x, final_y;
         finish, final_x, final_y = median(cx,cy);

         if finish == true then -- calculate the predicted angle once the median has been obtained
										  -- only enters if done accumulating frames
				local dx=final_x-_screenW/2
				local ang_pred_rad = torch.atan(dx/640)--THIS IS THE ZSCREEN VALUE
				local ang_pred_deg = ang_pred_rad * 180 / 3.1415
				
				--printMedian(ang_pred_deg, final_x, final_y)

				return ang_pred_deg

			end	

		end
	end
	
end

local frame_count = 3; -- number of frames to accumulate for median calculation
local array=torch.Tensor(2,frame_count); -- arrays to put in all the values accumulated
local num = 0; -- keep track of the number of frames already accumulated

function median(x_coord, y_coord)
        nil_count = 0;
	move_count = 0; -- reset nil_count and move_count once the robot has found the object
	array[1][num+1]=x_coord
	array[2][num+1]=y_coord
	num = num + 1;
	if num == frame_count then
		local sorted_array = torch.sort(array,2) -- sort the array in ascending order
		num = 0;
		return true, sorted_array[1][frame_count/2 + 0.5], sorted_array[2][frame_count/2 + 0.5] -- return the median
	else
		return false
	end
end

function look_around()
local n = 6
local lag = 12
	if move_count % lag == 0 then
		turn_bot(360/n)
	end
	move_count = move_count + 1;
	if(move_count == n*lag) then
		print("I can't find the object")
		move_count = 0;
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

