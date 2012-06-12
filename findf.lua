function printMedian(_options, _x, _y, _screenW)
	if _options.findfollow then 
			local cx = _x; local cy = _y;                
			local finish, final_x, final_y;
         finish, final_x, final_y = median(cx,cy);
         if finish == true then
				local dx=final_x-_screenW/2
				local ang_pred_rad = torch.atan(dx/640)--THIS IS THE ZSCREEN VALUE
				local ang_pred_deg = ang_pred_rad * 180 / 3.1415
				
				print('~~~~~~~FROM MEDIAN~~~~~~~~~~')
				state.logit('predicted angle='.. ang_pred_deg .. 'degrees at x:' .. cx .. ' y:' .. cy)				
				print('dx [measured]:',dx,'dx_fact',2*dx/_screenW)
				print('angle [calculated] :', ang_pred_deg,'degrees which is', ang_pred_rad, 'radians')
				print('median x:',final_x,' median y:', final_y)

				print('turning')
				turn_bot(ang_pred_deg)
				print('turned')
				move_forward()
			end
			
	end
end

-- variables needed for the median function
local frame_count = 3;
local array=torch.Tensor(2,frame_count);
local num = 0;
function median(x_coord, y_coord)
    array[1][num+1]=x_coord
    array[2][num+1]=y_coord
    num = num + 1;
    if num == frame_count then
        local sorted_array = torch.sort(array,2)
        num = 0;
        return true, sorted_array[1][frame_count/2 + 0.5], sorted_array[2][frame_count/2 + 0.5]
    else
        return false
    end
end
