format long g

global svplot=1;

function doplot(system1, system2, Flo, Fhi, name)
    global svplot;
    Fxaxis = logspace(floor(log10(Flo)), ceil(log10(Fhi)), 200);
    [mag(:,1), phase(:,1)] = bode(system1, 2*pi*Fxaxis);
    [mag(:,2), phase(:,2)] = bode(system2, 2*pi*Fxaxis);
    subplot(2,1,1);
    semilogx(Fxaxis, 20*log10(abs(mag)));
    axis([-Inf, Inf, -60, 0])
    grid on
    title(name)
    subplot(2,1,2);
    semilogx(Fxaxis, phase);
    axis([-Inf, Inf, -180, 180])
    grid on
    title(name)
    print(['foo' num2str(svplot) '.svg'], '-dsvg')
    print(['foo' num2str(svplot) '.pdf'], '-dpdfwrite')
    svplot += 1
end

for i = 1:2
    if i == 1
        name = 'Turn-by-turn to FA'
        decimationFactor = 152
        Fsample = 499.64e6 / 328
        Flo = 1000
        Fhi = 10000
    else
        name = 'FA to SA'
        decimationFactor = 500
        Fsample = 499.64e6 / 328 / 152 / 2
        Flo = 1
        Fhi = 10
    end
    cic1_num = ones(1, decimationFactor) / decimationFactor;
    cic1_den = [1, zeros(1, decimationFactor - 1)];
    sysCIC1 = tf(cic1_num, cic1_den , 1/Fsample);
    cic2_num = conv(cic1_num, cic1_num);
    cic2_den = conv(cic1_den, cic1_den);
    sysCIC2 = tf(cic2_num, cic2_den , 1/Fsample);

    doplot(sysCIC1, sysCIC2, Fsample/decimationFactor/100, Fsample/2, name)
    doplot(sysCIC1, sysCIC2, Flo, Fhi, name)
end
