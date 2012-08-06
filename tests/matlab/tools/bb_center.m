function center = bb_center(bb)
% Returns the central pixel [col,row] of the bounding box(es)

if isempty(bb)
	center = []; 
	return;
end

center = 0.5 * [bb(1,:)+bb(3,:); bb(2,:)+bb(4,:)];