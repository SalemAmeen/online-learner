function bb2 = bb_cut(bb1,N)

M = size(bb1,2);

% Fill
if M < N
    bb2 = bb1;
    bb2(:,end+1:end+N-M) = nan;
else
    bb2 = bb1(:,1:N);
end
