function [varargout]=fkxchorzvolume(rr,rt,tr,tt,smax,spts,frng,polar,w)
%FKXCHORZVOLUME    Returns frequency-wavenumber space for horz. xc data
%
%    Usage:    [rvol,tvol]=fkxchorzvolume(rr,rt,tr,tt,smax,spts,frng)
%              [rvol,tvol]=fkxchorzvolume(rr,rt,tr,tt,smax,spts,frng,polar)
%
%    Description: [RVOL,TVOL]=FKXCHORZVOLUME(RR,RT,TR,TT,SMAX,SPTS,FRNG)
%     calculates the Rayleigh & Love energy moving through an array in
%     frequency-wavenumber space utilizing the horizontal cross correlation
%     datasets RR, RT, TR & TT.  To allow for easier interpretation between
%     frequencies, the energy is mapped into frequency-slowness space.  The
%     array info and correlograms are contained in the SEIZMO structs RR,
%     RT, TR, & TT.  RR is expected to contain the pairwise radial-radial
%     correlations and TT is expected to contain the pairwise transverse
%     -transverse correlations (RT/TR give the radial-tranverse & the
%     transverse-radial components - energy on these records is indicative
%     of an anisotropic source distribution).  This also differs from
%     FKXCVOLUME in that horizontals are utilized to retreive both the
%     radial (RVOL) & transverse (TVOL) energy distributions.  FKXCVOLUME
%     does not account for the directional sensitivity of horizontals - it
%     is better suited for vertical components that do not vary in
%     directional sensitivity to plane waves with different propagation
%     directions.  The range of the slowness space is given by SMAX (in
%     s/deg) and extends from -SMAX to SMAX for both East/West and
%     North/South directions.  SPTS controls the number of slowness points
%     for both directions (SPTSxSPTS grid).  FRNG gives the frequency range
%     as [FREQLOW FREQHIGH] in Hz.  RVOL & TVOL are structs containing
%     relevant info and the frequency-slowness volume itself.  The struct
%     layout is:
%          .response - frequency-slowness array response
%          .nsta     - number of stations utilized in making map
%          .stla     - station latitudes
%          .stlo     - station longitudes
%          .stel     - station elevations (surface)
%          .stdp     - station depths (from surface)
%          .butc     - UTC start time of data
%          .eutc     - UTC end time of data
%          .npts     - number of time points
%          .delta    - number of seconds between each time point
%          .x        - east/west slowness or azimuth values
%          .y        - north/south or radial slowness values
%          .z        - frequency values
%          .polar    - true if slowness is sampled in polar coordinates 
%          .center   - array center or method
%          .normdb   - what 0dB actually corresponds to
%          .volume   - true if frequency-slowness volume (false for FKMAP)
%
%     Calling FKXCHORZVOLUME with no outputs will automatically slide
%     through the frequency-slowness volumes using FKFREQSLIDE.
%
%     [RVOL,TVOL]=FKXCHORZVOLUME(RR,RT,TR,TT,SMAX,SPTS,FRNG,POLAR) sets
%     if the slowness space is sampled regularly in cartesian or polar
%     coordinates.  Polar coords are useful for slicing the volume by
%     azimuth (pie slice) or slowness magnitude (rings).  Cartesian coords
%     (the default) samples the slowness space regularly in the East/West
%     & North/South directions and so exhibits less distortion of the
%     slowness space.
%
%    Notes:
%     - Records in RR, RT, TR, & TT must be correlograms following the
%       formatting from CORRELATE.  The records must have the same lag
%       range & sample spacing.  Furthermore, the datasets must be equal
%       sized and every record should correspond to the records with the
%       same index in the other datasets (ie RR(3), RT(3), TR(3) & TT(3)
%       must correspond to the same station pair).
%     - Best/quickest results are obtained when RR, RT, TR, & TT is one
%       "triangle" of the cross correlation matrix.
%     - The CENTER option (from FKVOLUME) is essentially 'coarray' here and
%       cannot be changed.
%
%    Examples:
%     One way to perform horizontal fk analysis:
%      enxc=correlate(e,n);
%      [b,e,delta]=getheader(enxc,'b','e','delta');
%      enxc=interpolate(enxc,delta(1),'spline',max(b),min(e));
%      rtxc=rotate_correlations(enxc);
%      [rvol,tvol]=fkxchorzvolume(rtxc(1:4:end),rtxc(2:4:end),...
%          rtxc(3:4:end),rtxc(4:4:end),50,101,[1/50 1/20]);
%      fkfreqslide(rvol,0);
%      fkfreqslide(tvol,0);
%
%    See also: FKXCVOLUME, FKFREQSLIDE, FKMAP, FK4D, FKVOL2MAP, FKSUBVOL,
%              FKVOLUME, CORRELATE, ROTATE_CORRELATIONS

%     Version History:
%        June  9, 2010 - initial version
%        June 12, 2010 - math is sound now
%        June 13, 2010 - passes several eq verifications
%        June 16, 2010 - allow any form of cross correlation matrix (not
%                        just one triangle), doc update, add example
%        June 18, 2010 - add weights
%        June 22, 2010 - default weights
%        July  1, 2010 - high latitude fix
%
%     Written by Garrett Euler (ggeuler at wustl dot edu)
%     Last Updated July  1, 2010 at 14:05 GMT

% todo:

% check nargin
error(nargchk(7,9,nargin));

% define some constants
d2r=pi/180;
d2km=6371*d2r;

% check struct
versioninfo(rr,'dep');
versioninfo(rt,'dep');
versioninfo(tr,'dep');
versioninfo(tt,'dep');

% make sure rr/tt are the same size
ncorr=numel(rr);
ncorr1=numel(tt);
ncorr2=numel(tt);
ncorr3=numel(tt);
if(~isequal(ncorr,ncorr1,ncorr2,ncorr3))
    error('seizmo:fkxchorzvolume:unmatchedXCdata',...
        'XC datasets do not match in size!');
end

% defaults for optionals
if(nargin<8 || isempty(polar)); polar=false; end
if(nargin<9 || isempty(w)); w=ones(ncorr,1); end
center='coarray';

% check inputs
sf=size(frng);
if(~isreal(smax) || ~isscalar(smax) || smax<=0)
    error('seizmo:fkxchorzvolume:badInput',...
        'SMAX must be a positive real scalar in s/deg!');
elseif(~any(numel(spts)==[1 2]) || any(fix(spts)~=spts) || any(spts<=2))
    error('seizmo:fkxchorzvolume:badInput',...
        'SPTS must be a positive scalar integer >2!');
elseif(~isreal(frng) || numel(sf)~=2 || sf(2)~=2 || any(frng(:)<=0))
    error('seizmo:fkxchorzvolume:badInput',...
        'FRNG must be a Nx2 array of [FREQLOW FREQHIGH] in Hz!');
elseif(~isscalar(polar) || (~islogical(polar) && ~isnumeric(polar)))
    error('seizmo:fkxchorzvolume:badInput',...
        'POLAR must be TRUE or FALSE!');
elseif(numel(w)~=ncorr || any(w(:)<0) || ~isreal(w) || sum(w(:))==0)
    error('seizmofkxcvolume:badInput',...
        'WEIGHTS must be equal sized with XCDATA & be positive numbers!');
end
nrng=sf(1);

% convert weights to row vector
w=w(:).';
sw=sum(w);

% turn off struct checking
oldseizmocheckstate=seizmocheck_state(false);

% attempt header check
try
    % check headers
    rr=checkheader(rr,...
        'MULCMP_DEP','ERROR',...
        'NONTIME_IFTYPE','ERROR',...
        'FALSE_LEVEN','ERROR',...
        'MULTIPLE_DELTA','ERROR',...
        'MULTIPLE_NPTS','ERROR',...
        'MULTIPLE_B','ERROR',...
        'UNSET_ST_LATLON','ERROR',...
        'UNSET_EV_LATLON','ERROR');
    rt=checkheader(rt,...
        'MULCMP_DEP','ERROR',...
        'NONTIME_IFTYPE','ERROR',...
        'FALSE_LEVEN','ERROR',...
        'MULTIPLE_DELTA','ERROR',...
        'MULTIPLE_NPTS','ERROR',...
        'MULTIPLE_B','ERROR',...
        'UNSET_ST_LATLON','ERROR',...
        'UNSET_EV_LATLON','ERROR');
    tr=checkheader(tr,...
        'MULCMP_DEP','ERROR',...
        'NONTIME_IFTYPE','ERROR',...
        'FALSE_LEVEN','ERROR',...
        'MULTIPLE_DELTA','ERROR',...
        'MULTIPLE_NPTS','ERROR',...
        'MULTIPLE_B','ERROR',...
        'UNSET_ST_LATLON','ERROR',...
        'UNSET_EV_LATLON','ERROR');
    tt=checkheader(tt,...
        'MULCMP_DEP','ERROR',...
        'NONTIME_IFTYPE','ERROR',...
        'FALSE_LEVEN','ERROR',...
        'MULTIPLE_DELTA','ERROR',...
        'MULTIPLE_NPTS','ERROR',...
        'MULTIPLE_B','ERROR',...
        'UNSET_ST_LATLON','ERROR',...
        'UNSET_EV_LATLON','ERROR');
    
    % turn off header checking
    oldcheckheaderstate=checkheader_state(false);
catch
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    
    % rethrow error
    error(lasterror)
end

% do fk analysis
try
    % verbosity
    verbose=seizmoverbose;
    
    % require radial & transverse components
    [rrmcn,rrscn]=getheader(rr,'kt3','kcmpnm');
    [rtmcn,rtscn]=getheader(rt,'kt3','kcmpnm');
    [trmcn,trscn]=getheader(tr,'kt3','kcmpnm');
    [ttmcn,ttscn]=getheader(tt,'kt3','kcmpnm');
    rrmcn=char(rrmcn); rrmcn=rrmcn(:,3);
    rrscn=char(rrscn); rrscn=rrscn(:,3);
    rtmcn=char(rtmcn); rtmcn=rtmcn(:,3);
    rtscn=char(rtscn); rtscn=rtscn(:,3);
    trmcn=char(trmcn); trmcn=trmcn(:,3);
    trscn=char(trscn); trscn=trscn(:,3);
    ttmcn=char(ttmcn); ttmcn=ttmcn(:,3);
    ttscn=char(ttscn); ttscn=ttscn(:,3);
    if(~isequal(lower(unique(rrmcn)),'r') ...
            || ~isequal(lower(unique(rrscn)),'r'))
        error('seizmo:fkxchorzvolume:badRR',...
            'RR does not appear to be Radial-Radial XC data!');
    elseif(~isequal(lower(unique(rtmcn)),'r') ...
            || ~isequal(lower(unique(rtscn)),'t'))
        error('seizmo:fkxchorzvolume:badRT',...
            'RT does not appear to be Radial-Transverse XC data!');
    elseif(~isequal(lower(unique(trmcn)),'t') ...
            || ~isequal(lower(unique(trscn)),'r'))
        error('seizmo:fkxchorzvolume:badTR',...
            'TR does not appear to be Transverse-Radial XC data!');
    elseif(~isequal(lower(unique(ttmcn)),'t') ...
            || ~isequal(lower(unique(ttscn)),'t'))
        error('seizmo:fkxchorzvolume:badTT',...
            'TT does not appear to be Transverse-Transverse XC data!');
    end
    
    % get station locations & require that they match
    [st1,ev1]=getheader(rr,'st','ev');
    [st2,ev2]=getheader(rt,'st','ev');
    [st3,ev3]=getheader(tr,'st','ev');
    [st4,ev4]=getheader(tt,'st','ev');
    if(~isequal([st1; ev1],[st2; ev2],[st3; ev3],[st4; ev4]))
        error('seizmo:fkxchorzvolume:xcDataMismatch',...
            'XC Datasets have different station locations!');
    end
    clear st2 st3 st4 ev2 ev3 ev4
    
    % find unique station locations
    loc=unique([st1; ev1],'rows');
    nsta=size(loc,1);
    
    % require all records to have equal b, npts, delta
    [b,npts,delta]=getheader([rr(:); rt(:); tr(:); tt(:)],...
        'b','npts','delta');
    if(~isscalar(unique(b)) ...
            || ~isscalar(unique(npts)) ...
            || ~isscalar(unique(delta)))
        error('seizmo:fkxchorzvolume:badData',...
            'XC records must have equal B, NPTS & DELTA fields!');
    end
    npts=npts(1); delta=delta(1);
    
    % check nyquist
    fnyq=1/(2*delta(1));
    if(any(frng>=fnyq))
        error('seizmo:fkxchorzvolume:badFRNG',...
            ['FRNG frequencies must be under the nyquist frequency (' ...
            num2str(fnyq) ')!']);
    end
    
    % setup output
    [rvol(1:nrng,1).nsta]=deal(nsta);
    [rvol(1:nrng,1).stla]=deal(loc(:,1));
    [rvol(1:nrng,1).stlo]=deal(loc(:,2));
    [rvol(1:nrng,1).stel]=deal(loc(:,3));
    [rvol(1:nrng,1).stdp]=deal(loc(:,4));
    [rvol(1:nrng,1).butc]=deal([0 0 0 0 0]);
    [rvol(1:nrng,1).eutc]=deal([0 0 0 0 0]);
    [rvol(1:nrng,1).delta]=deal(delta);
    [rvol(1:nrng,1).npts]=deal(npts);
    [rvol(1:nrng,1).polar]=deal(polar);
    [rvol(1:nrng,1).center]=deal(center);
    [rvol(1:nrng,1).volume]=deal(true);
    
    % get frequencies (note no extra power for correlations)
    nspts=2^nextpow2(npts);
    f=(0:nspts/2)/(delta*nspts);  % only +freq
    
    % extract data (silently)
    seizmoverbose(false);
    rr=splitpad(rr,0);
    rr=records2mat(rr);
    rt=splitpad(rt,0);
    rt=records2mat(rt);
    tr=splitpad(tr,0);
    tr=records2mat(tr);
    tt=splitpad(tt,0);
    tt=records2mat(tt);
    seizmoverbose(verbose);
    
    % get fft (conjugate is b/c my xc is flipped?)
    % - this is the true cross spectra
    rr=conj(fft(rr,nspts,1));
    rt=conj(fft(rt,nspts,1));
    tr=conj(fft(tr,nspts,1));
    tt=conj(fft(tt,nspts,1));
    
    % get relative positions of center
    % r=(x  ,y  )
    %     ij  ij
    %
    % position of j as seen from i
    % x is km east
    % y is km north
    %
    % Note: this does NOT handle polar arrays!
    %
    % r is 2xNCORR
    [clat,clon]=arraycenter(loc(:,1),loc(:,2));
    [e_ev,n_ev]=geographic2enu(ev1(:,1),ev1(:,2),0,clat,clon,0);
    [e_st,n_st]=geographic2enu(st1(:,1),st1(:,2),0,clat,clon,0);
    r=[e_st-e_ev n_st-n_ev]';
    clear e_ev e_st n_ev n_st
    
    % make slowness projection arrays
    %
    % p=2*pi*i*s*r
    %
    % where s is the slowness vector s=(s ,s ) and is NSx2
    %                                    x  y
    %
    % Note s is actually a collection of slowness vectors who
    % correspond to the slownesses that we want to inspect in
    % the fk analysis.  So p is actually the projection of all
    % slownesses onto all of the position vectors (multiplied
    % by 2*pi*i so we don't have to do that for each frequency
    % later)
    %
    % u=cos(theta)
    % v=sin(theta)
    %
    % where theta is the angle from the position vector to the slowness
    % vector with positive being in the counter-clockwise direction
    % 
    % ie. theta = atan2(sy,sx)-atan2(ry,rx)
    %
    % p,u,v are NSxNCORR
    smax=smax/d2km;
    if(polar)
        if(numel(spts)==2)
            bazpts=spts(2);
            spts=spts(1);
        else
            bazpts=181;
        end
        smag=(0:spts-1)/(spts-1)*smax;
        [rvol(1:nrng,1).y]=deal(smag'*d2km);
        smag=smag(ones(bazpts,1),:)';
        baz=(0:bazpts-1)/(bazpts-1)*360*d2r;
        [rvol(1:nrng,1).x]=deal(baz/d2r);
        baz=baz(ones(spts,1),:);
        p=2*pi*1i*[smag(:).*sin(baz(:)) smag(:).*cos(baz(:))]*r;
        % u = cos theta
        % v = sin theta
        theta1=atan2(r(2,:),r(1,:));
        theta2=baz(:);
        theta=theta2(:,ones(ncorr,1))-theta1(ones(spts*bazpts,1),:);
        u=cos(theta);
        v=sin(theta);
        % fix for s==0 (accept all azimuths b/c no directional dependance
        % in response on vertical traveling waves)
        zeroslow=smag(:)==0;
        u(zeroslow,:)=1;
        v(zeroslow,:)=1;
        clear r smag baz zeroslow theta theta1 theta2
    else % cartesian
        spts=spts(1); bazpts=spts;
        sx=-smax:2*smax/(spts-1):smax;
        [rvol(1:nrng,1).x]=deal(sx*d2km);
        [rvol(1:nrng,1).y]=deal(fliplr(sx*d2km)');
        sx=sx(ones(spts,1),:);
        sy=fliplr(sx)';
        p=2*pi*1i*[sx(:) sy(:)]*r;
        % u = cos theta
        % v = sin theta
        theta1=atan2(r(2,:),r(1,:));
        theta2=atan2(sy(:),sx(:));
        theta=theta2(:,ones(ncorr,1))-theta1(ones(spts^2,1),:);
        u=cos(theta);
        v=sin(theta);
        % fix for s==0 (accept all azimuths b/c no directional dependance
        % in response on vertical traveling waves)
        zeroslow=sy(:)==0 & sx(:)==0;
        u(zeroslow,:)=1;
        v(zeroslow,:)=1;
        clear r sx sy zeroslow theta theta1 theta2
    end
    
    % copy rvol to tvol
    tvol=rvol;
    
    % loop over frequency ranges
    for a=1:nrng
        % get frequencies
        fidx=find(f>=frng(a,1) & f<=frng(a,2));
        rvol(a).z=f(fidx);
        tvol(a).z=f(fidx);
        nfreq=numel(fidx);
        
        % preallocate fk space
        rvol(a).response=zeros(spts,bazpts,nfreq,'single');
        tvol(a).response=zeros(spts,bazpts,nfreq,'single');
        
        % warning if no frequencies
        if(~nfreq)
            warning('seizmo:fkxchorzvolume:noFreqs',...
                'No frequencies within the range %g to %g Hz!',...
                frng(a,1),frng(a,2));
            continue;
        end
        
        % detail message
        if(verbose)
            fprintf('Getting fk Volume %d for %g to %g Hz\n',...
                a,frng(a,1),frng(a,2));
            print_time_left(0,nfreq);
        end
        
        % loop over frequencies
        for b=1:nfreq
            % current freq idx
            cf=fidx(b);
            
            % get response
            % - Following Koper, Seats, and Benz 2010 in BSSA
            %   by only using the real component.  This matches
            %   best with the beam from doing a 'center' style
            %   beam like the Gerstoft group does but gives
            %   slightly better results (at the cost of (N-1)/2
            %   times more operations).  This is required when
            %   using correlation datasets.
            
            % rotate data into direction of plane wave for every pairing
            data=u.*u.*rr(cf*ones(1,spts*bazpts),:) ...
                -u.*v.*rt(cf*ones(1,spts*bazpts),:) ...
                -v.*u.*tr(cf*ones(1,spts*bazpts),:) ...
                +v.*v.*tt(cf*ones(1,spts*bazpts),:);
            
            % normalize by auto spectra
            data=data./abs(data);
            
            % apply weights
            data=data.*w(ones(1,spts*bazpts),:);
            
            % now getting fk response for radial (rayleigh)
            rvol(a).response(:,:,b)=reshape(10*log10(abs(real(...
                sum(data.*exp(f(cf)*p),2)))/sw),spts,bazpts);
            
            % rotate data perpendicular to plane wave direction for all
            data=v.*v.*rr(cf*ones(1,spts*bazpts),:) ...
                +v.*u.*rt(cf*ones(1,spts*bazpts),:) ...
                +u.*v.*tr(cf*ones(1,spts*bazpts),:) ...
                +u.*u.*tt(cf*ones(1,spts*bazpts),:);
            
            % normalize by auto spectra
            data=data./abs(data);
            
            % apply weights
            data=data.*w(ones(1,spts*bazpts),:);
            
            % now getting fk response for tangential (love)
            tvol(a).response(:,:,b)=reshape(10*log10(abs(real(...
                sum(data.*exp(f(cf)*p),2)))/sw),spts,bazpts);
            
            % detail message
            if(verbose); print_time_left(b,nfreq); end
        end
        
        % normalize so max peak is at 0dB
        rvol(a).normdb=max(rvol(a).response(:));
        rvol(a).response=rvol(a).response-rvol(a).normdb;
        tvol(a).normdb=max(tvol(a).response(:));
        tvol(a).response=tvol(a).response-tvol(a).normdb;
        
        % plot if no output
        if(~nargout)
            fkfreqslide(rvol(a));
            fkfreqslide(tvol(a));
        end
    end
    
    % return struct
    if(nargout); varargout{1}=rvol; varargout{2}=tvol; end
    
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    checkheader_state(oldcheckheaderstate);
catch
    % toggle checking back
    seizmocheck_state(oldseizmocheckstate);
    checkheader_state(oldcheckheaderstate);
    
    % rethrow error
    error(lasterror)
end

end