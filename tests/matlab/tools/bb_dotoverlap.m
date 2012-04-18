function overlap = bb_dotoverlap(bb1, bb2)
% Overlap of corresponding bboxes.

L1 = bb1(1,:); L2 = bb2(1,:);
B1 = bb1(4,:); B2 = bb2(4,:);
R1 = bb1(3,:); R2 = bb2(3,:);
T1 = bb1(2,:); T2 = bb2(2,:);

intersection = (max(0, min(R1, R2) - max(L1, L2) + 1)) .* ...
               (max(0, min(B1, B2) - max(T1, T2) + 1 ));
area1        = (R1-L1+1).*(B1-T1+1);
area2        = (R2-L2+1).*(B2-T2+1);
overlap      = intersection ./ (area1 + area2 - intersection);
