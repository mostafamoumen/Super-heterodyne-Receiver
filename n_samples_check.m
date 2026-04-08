info1 = audioinfo('Short_FM9090.wav');
info2 = audioinfo('Short_BBCArabic2.wav');

n_samples1 = info1.TotalSamples;
n_channels1 = info1.NumChannels;

n_samples2 = info2.TotalSamples;
n_channels2 = info2.NumChannels;

disp(n_samples1)
disp(n_channels1)

disp(n_samples2)
disp(n_channels2)
% this was just for testing ,,,(n_samples1=697536, n_samples2=740544 so we had to zeropad at the end of the shorter one)