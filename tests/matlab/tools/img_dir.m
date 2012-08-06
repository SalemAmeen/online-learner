function files = img_dir(path)

ext = {'*.jpeg','*.jpg','*.png','*.pgm'};
files = [];
for i = 1:length(ext)
    files = [files dir([path ext{i}])];
end

for i = 1:length(files)
    files(i).name = [path files(i).name];
end
