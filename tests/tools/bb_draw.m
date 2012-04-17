function bb_draw(bb1,varargin)
% Draw

if isempty(bb1), return; end;
idx = find(bb_isdef(bb1));
if isempty(varargin)
    varargin = {'edgecolor','y'};
end
for i = 1:length(idx)
    bb = bb1(:,idx(i));
    if bb(3)-bb(1) > 0 && bb(4)-bb(2)>0
        rectangle('Position',[bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)],varargin{:})
        
        if size(bb,1) == 5
            cp = bb_center(bb);
            text(cp(1),cp(2),num2str(bb(5),3),'color','w');
        end
        
    end
end