require 'kinect'
-- Initialize the Kinect
kinect.initDevice()

-- Robot mover program
local path = "~/ros_workspace/robot_mover/bin/robot_mover "
-- Needed by the robot mover
local command_path = 'export ROS_MASTER_URI=http://10.42.43.30:11311;'


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



function turn_bot(_angle)
	_angle = _angle*-1
	local exec_path = path..'0 '.._angle
	os.execute(command_path..exec_path)
return 0;
end

function move_forward()
    local b=kinect.getDepth()
    c=b:narrow(3,125,390)
    local min = torch.min(c)

    local count = 0;
    for i=1,9 do
        count = count + 1;
        if min >= thres[i] and min < thres[i+1] then
            break
        end
    end

    local distance = dist[count] + slope[count]*(min-thres[count])
    print("Distance estimated:",distance)

    while(distance >= 0.6) do
        local distance_to_move = distance - 0.6
        if(distance_to_move < 0.1) then
    	    distance_to_move = 0;
        end

        local full_path = path..distance_to_move.." 0"
        os.execute(command_path..full_path)

        b=kinect.getDepth()
        c=b:narrow(3,125,390)
        min = torch.min(c)
        count = 0;
        for i=1,9 do
            count = count + 1;
	     if min >= thres[i] and min < thres[i+1] then
	         break
	     end
    end

        distance = dist[count] + slope[count]*(min-thres[count])
        print("Distance estimated:",distance)
    end
end
