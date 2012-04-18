function bb = bb_shift_relative(bb,shift)
% Change

if isempty(bb)
    return;
end

shW = bb_width(bb)*shift(1);
shH = bb_height(bb)*shift(2);

bb(1,:) = bb(1,:) + shW;
bb(2,:) = bb(2,:) + shH;
bb(3,:) = bb(3,:) + shW;
bb(4,:) = bb(4,:) + shH;
