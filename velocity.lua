local velocity = {}

function velocity.compute_velocity()
	local x_move, y_move, x_velocity, y_velocity
	for i=1,#state.results do
		if state.results_prev[i] then
			x_move = state.results[i].cx - state.results_prev[i].cx
			y_move = state.results[i].cy - state.results_prev[i].cy
			x_velocity = x_move / state.frame_time
			y_velocity = y_move / state.frame_time
			--str = string.format(state.results[i].class..' x_velocity %f y_velocity %f',x_velocity,y_velocity)
			--state.logit(str)
		end
	end
	
end

return velocity
