local calib = {}

function calib.decideMsg(_options)
	if _options.rcalib ~= 0 then
		printCalibMsg(_options)
	elseif _options.zscreen ~= 0 then
		printAngleMsg()
	end
end


function printCalibMsg(_opt)

	print('\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++')
	print('Entered into angle calibration mode, for centering\n')
	print('You chose a ratio of', _opt.rcalib, 'degrees\n')
	print('Please write down z_screen [calculated] when it stabilizes!')
	print('+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n')
end

function printAngleMsg()

	print('\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++')
	print('Entered into angle estimation mode, for centering\n')
	print('++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++cx+\n')
end

function calib.decideDist(_options, _x, _y, _screenW)
		if _options.rcalib ~= 0 then
						
			--If we're calibrating, we want to calculate 
			--how far from the center of the frame the obj is!
			-------------------------------------------------------------------
			local cx = _x; local cy = _x
			local dx=cx-_screenW/2
			--local dy=cy-raw_h/2 -- this isn't needed yet
			--the robot can only turn left and right, no tilt

 			--uses trig to calculate the approximate distance between
			--the focal point of the camera and the camera's screen
			local z_screen = dx/_options.rcalib
				
			print('registered cursor at x:', cx,'y:',cy)
			state.logit('calibrated z_screen='.. z_screen .. ' at x:' .. cx .. ' y:' .. cy)				
			print('dx [measured]:',dx,'dx_fact',2*dx/_screenW)
			print('z_screen [calculated] :', z_screen)
			-------------------------------------------------------------------
		elseif _options.zscreen ~= 0 then
			--This section returns a predicted angle off center
			----------------------------------------------------------------------
			local cx = _x; local cy = _y;
                        
				local dx=cx-_screenW/2
				--local dy=cy-raw_h/2 -- this isn't needed yet
				--the robot can only turn left and right, no tilt

				--uses trig to calculate the approximate angle between
				--the focal point of the camera and the cursor
				local ang_pred_rad = torch.atan(dx/_options.zscreen)
				local ang_pred_deg = ang_pred_rad * 180 / 3.1415
				
				print('registered cursor at x:', cx,'y:',cy)
				state.logit('predicted angle='.. ang_pred_deg .. 'degrees at x:' .. cx .. ' y:' .. cy)				
				print('dx [measured]:',dx,'dx_fact',2*dx/_screenW)
				print('angle [calculated] :', ang_pred_deg,'degrees which is', ang_pred_rad, 'radians')

				print('turning')
				--turn_bot(ang_pred_deg)
				print('turned')
				-- move_forward()
                       
			state.learn = nil
		end
end

return calib
