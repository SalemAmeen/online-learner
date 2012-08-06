require 'inline'

local findf = {}

inline.preamble [[
	#include<sys/stat.h>
	#include<sys/mman.h>
	#include<fcntl.h>
	#include<unistd.h>
	#include<stdbool.h>

	typedef struct image_data{
		unsigned char data[640*480*3];
	}image_data;

	typedef struct depth_data{
		float data[640*480];
	}depth_data;
]]

findf.set_flag = inline.load [[
	bool* shared_ptr;
	int fd = shm_open("/OL_flag", (O_RDWR), (S_IRUSR|S_IWUSR));
	shared_ptr = (bool*)mmap(0, sizeof(bool), (PROT_READ|PROT_WRITE), MAP_SHARED, fd, 0);
	lockf(fd, F_LOCK, sizeof(bool));
	*shared_ptr = true;
	lockf(fd, F_ULOCK, sizeof(bool));
	shm_unlink("/OL_flag");
]]

findf.unset_flag = inline.load [[
	bool* shared_ptr;
	int fd = shm_open("/OL_flag", (O_RDWR), (S_IRUSR|S_IWUSR));
	shared_ptr = (bool*)mmap(0, sizeof(bool), (PROT_READ|PROT_WRITE), MAP_SHARED, fd, 0);
	lockf(fd, F_LOCK, sizeof(bool));
	*shared_ptr = false;
	lockf(fd, F_ULOCK, sizeof(bool));
	shm_unlink("/OL_flag");
]]

findf.getRosImage = inline.load [[
	image_data* mapped_ptr;
	int fd = shm_open("/rgb_image_share", (O_RDWR), (S_IRUSR|S_IWUSR));
	
	THFloatTensor* float_tensor = luaT_checkudata(L,1,luaT_checktypename2id(L,"torch.FloatTensor"));
	float *c_tensor = THFloatTensor_data(float_tensor);
	
	int width_inc = float_tensor->stride[2];
	int height_inc = float_tensor->stride[1];
	int dim_inc = float_tensor->stride[0];
	lockf(fd,F_LOCK,sizeof(image_data));
	mapped_ptr = (image_data*)mmap(0, sizeof(image_data), (PROT_READ|PROT_WRITE), MAP_SHARED, fd, 0);
	int i,j,num;
	for(i=0; i<480; i++){
		for(j=0; j<640; j++){
			num = i*height_inc+j*width_inc;
			c_tensor[num] = ((unsigned int)(mapped_ptr->data[i*(3*640)+j*3]))/255.0;
			c_tensor[dim_inc + num] = ((unsigned int)(mapped_ptr->data[i*(3*640)+j*3+1]))/255.0;
			c_tensor[dim_inc*2 + num] = ((unsigned int)(mapped_ptr->data[i*(3*640)+j*3+2]))/255.0;
		}
	}
	lockf(fd,F_ULOCK,sizeof(image_data));
]]

findf.getRosDepthImage = inline.load [[
	depth_data* mapped_ptr;
	int fd = shm_open("/depth_image_share", (O_RDWR), (S_IRUSR|S_IWUSR));
	
	THFloatTensor* float_tensor = luaT_checkudata(L,1,luaT_checktypename2id(L,"torch.FloatTensor"));
	float *c_tensor = THFloatTensor_data(float_tensor);
	
	int width_inc = float_tensor->stride[1];
	int height_inc = float_tensor->stride[0];
	lockf(fd,F_LOCK,sizeof(depth_data));
	mapped_ptr = (depth_data*)mmap(0, sizeof(depth_data), (PROT_READ|PROT_WRITE), MAP_SHARED, fd, 0);
	int i,j,num;
	for(i=0; i<480; i++){
		for(j=0; j<640; j++){
			num = i*height_inc+j*width_inc;
			c_tensor[num] = mapped_ptr->data[i*640+j];
		}
	}
	lockf(fd,F_ULOCK,sizeof(depth_data));
]]



local z_screen_DEBUG = 500; --kinect:500--usb:640;

local nil_count = 0; -- counts the number of times no result is generated
local turn_count = 0; -- tracks which movement the robot needs to make

local turn_lag = 12 -- the number of frames before the robot continues to turn
local turn_angle_incr = 30 --(degrees) the amount the robot turns when looking around

local no_object_frames = 40; -- constant for how many frames of no object before the robot goes looking around
local median_frames = 3; -- number of frames to accumulate for median calculation
local mid_indx;
if median_frames % 2 ==0 then
	mid_indx = median_frames/2+1
else
	mid_indx = median_frames/2+.5
end

local array=torch.Tensor(2,median_frames); -- arrays to put in all the values accumulated
local xy_array=torch.Tensor(2,median_frames); 
local num_frames = 0; -- keep track of the number of frames already accumulated

local left_right = -1; -- the object is at the left or right at the most recent frame, 1 means left, -1 means right

function findf.findMedian(_options, _x, _y, _screenW)
--returns the median angle from a 
	
	local cx = _x; local cy = _y;
   if cx == -1 and cy == -1 then -- no result
		nil_count = nil_count + 1;
      if nil_count >= no_object_frames then
      	num_frames = 0; --resets the median count
			print('lost object');
			bot.smooth_stop();
			--print('smooooooth stop');

			--turn this back on later maybe?			
			findf.look_around()
			
			--Turns off OL flag in shared memory
			--unset_flag();			
		end

	else --if there is a result
		local isArrayFull, final_x, final_y;
      isArrayFull, final_x, final_y = findf.median(cx,cy);

      if isArrayFull == true then -- calculate the predicted angle once the median has been obtained
										  -- only enters if done accumulating frames
			local dx=final_x-_screenW/2
			local ang_pred_rad = torch.atan(dx/z_screen_DEBUG)--THIS IS THE ZSCREEN VALUE
			local ang_pred_deg = ang_pred_rad * 180 / 3.1415
				
			--printMedian(ang_pred_deg, final_x, final_y)

			return ang_pred_deg
		end	
	end
end



function findf.median(x_coord, y_coord)
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
	if num_frames == median_frames then
		--Actually calculates the median here
		--TO DO: allow to work with even numbers of frames
		local sorted_array = torch.sort(array,2) -- sort the array in ascending order
		num_frames = 0;
		return true, sorted_array[1][mid_indx], sorted_array[2][mid_indx] -- return the median
	else 
		return false
	end
end


function findf.look_around()
	local n = 360/turn_angle_incr
	if turn_count % turn_lag == 0 then
		bot.turn_bot(left_right*turn_angle_incr) -- if it's left, then the argument is negative, if it's right, then the argument is positive
		--findf.playBeep(1)
	end
	turn_count = turn_count + 1;
	if(turn_count == n*turn_lag) then
		print("I can't find the object")
		turn_count = 0;
		--playBeep(4)
	end
end

function findf.playBeep(beepNum)
	os.execute("/usr/bin/mplayer ~/online-learner/sound/beep-"..beepNum..".wav&")
end

function findf.printMedian(ang_pred_deg, fx, fy)
	print('~~~~~~~FROM MEDIAN~~~~~~~~')
	print('angle [calculated] :', ang_pred_deg,'degrees')
	print('median x:',f_x,' median y:', f_y)
	state.logit('predicted angle='.. ang_pred_deg .. 'degrees at x:' .. fx .. ' y:' .. fy)			
end	

return findf
