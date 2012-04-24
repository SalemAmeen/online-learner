function [prec, rec,ovrlp] = bb_performance(gt,bb,thr)
% Precision and Recall of BB and GT.

Ngt = size(gt,2);
Nbb = size(bb,2);

if Nbb < Ngt, bb = [bb nan(4,Ngt-Nbb)]; end
if Nbb > Ngt, bb = bb(:,1:Ngt); end

gton  = isfinite(gt(1,:));
bbon  = isfinite(bb(1,:));

ovrlp = bb_dotoverlap(gt,bb);

TP    = ovrlp > thr;

prec  = sum(TP) / sum(bbon);
rec   = sum(TP) / sum(gton);

% 
% 
% err = bb_error(gt,bb);
% 
% FP = gton==0 & bbon ==1;
% err(FP) = 5;
