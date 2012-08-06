--Written by Adam Willats and Yu Chen Lim
local bot = {}

-- Robot mover program
local path = "~/ros_workspace/robot_mover/bin/basic_mover "
local path_smooth = "~/ros_workspace/robot_mover/bin/smooth_mover "
-- Needed by the robot mover
local command_path = 'export ROS_MASTER_URI=http://10.42.43.30:11311;'
os.execute(command_path.."~/ros_workspace/turtlebot_init/bin/turtlebot_init")
os.execute("sleep 3")

if options.source ~= 'kinect' then
	require 'kinect'
	-- Initialize the Kinect
	--kinect.initDevice()
end

--Movement constants
local min_obj_dist = .5 --(in meters) the minimum distance 
							 --the kinect will allow between the camera and the object

local max_obj_dist = .1 -- (in meters)


local min_move_dist = 0.01 --movement distances smaller than this are considered 0s
local min_move_angle = 1 --(in degrees)
--Screen constants
local scr_w=640 --the width of the screen, in pixels
local window=390 --the number of pixels from the middle of the frame to be taken
local margin=(scr_w-window)/2
local box=20
local half_box=box/2

--NOTE: maybe move all these constants to a separate data file
-- Constant declaration
-- Distance in meters
local dist1 = 0.5
local dist2 = 0.62
local dist3 = 0.75
local dist4 = 1
local dist5 = 1.25
local dist6 = 1.5
local dist7 = 1.75
local dist8 = 2
local dist9 = 2.25
local dist10 = 2.5
local dist = {dist1, dist2, dist3, dist4, dist5, dist6, dist7, dist8, dist9, dist10}

-- Kinect data corresponding to the distance
local thres1 = 0.193
local thres2 = 0.256
local thres3 = 0.3075
local thres4 = 0.3625
local thres5 = 0.397
local thres6 = 0.4191
local thres7 = 0.4358
local thres8 = 0.4475
local thres9 = 0.4575
local thres10 = 0.4651
local thres = {thres1, thres2, thres3, thres4, thres5, thres6, thres7, thres8, thres9, thres10}

-- Piecewise slope
local slope1_2 = 1.9048
local slope2_3 = 2.1834
local slope3_4 = 4.5455
local slope4_5 = 7.2464
local slope5_6 = 11.3122
local slope6_7 = 14.9701
local slope7_8 = 21.3675
local slope8_9 = 25
local slope9_10 = 32.8947
local slope = {slope1_2, slope2_3, slope3_4, slope4_5, slope5_6, slope6_7, slope7_8, slope8_9, slope9_10}

local numThresh = table.getn(thres)

function bot.turn_bot(_angle)
	if math.abs(_angle) > min_move_angle then
	
		_angle = _angle*-1
		local exec_path = path..'0 '.._angle
		os.execute(command_path..exec_path)
		return 0;
	else
		return 1;
	end	
end

function bot.get_distance(kinect_value)
	local count = 0;
	if kinect_value < thres[1] then
		return 0.5
	end
	--checks where the distance value is in relation to the thresholds
   for i=1,numThresh-1 do
       count = count + 1;
       if kinect_value >= thres[i] and kinect_value < thres[i+1] then
           break
       end
   end

	--calculates distance based on linear interpolation
   local est_dist = dist[count] + slope[count]*(kinect_value-thres[count])
	return est_dist
end

function bot.full_move(angle)
	if math.abs(angle) > min_move_angle then
		angle = angle*-1
	else
		angle = 0
	end
	local cx = state.results[1].cx
	local cy = state.results[1].cy
	print("Online-learner getting depth data")
	local depthFrame = torch.FloatTensor(480,640);
	findf.getRosDepthImage(depthFrame);
	if cx-half_box < 0 then
		cx = half_box
	end
	if cy-half_box < 0 then
		cy = half_box
	end
	if cx+half_box > 640 then
		cx = 640-half_box
	end
	if cy+half_box > 480 then
		cy = 480-half_box
	end
   local intermediate_depth = depthFrame:narrow(2,cx-half_box,box)
	local depth = intermediate_depth:narrow(1,cy-half_box,box)
	--local intermediate_depth = source.depthFrame:narrow(3,cx-half_box,box)
	--local depth = depthFrame:narrow(3,margin,window)
	local distance=torch.min(depth)
	--local distance=bot.get_distance(min)
	local dist_to_move = 0
	if (distance >= (min_obj_dist+min_move_dist)) then --too far
		dist_to_move = distance - min_obj_dist

	elseif (distance < max_obj_dist-min_move_dist) then --too close
		dist_to_move = distance - max_obj_dist
	end

	--executes movement command
	local full_path = path_smooth..dist_to_move.." "..angle.."&"
	print(full_path)
	os.execute("killall smooth_mover;"..command_path..full_path)
end

function bot.smooth_stop()
	local full_path = path_smooth.."0.1".."&"
	--print(full_path)
	os.execute("killall smooth_mover;"..command_path..full_path)
end

return bot
