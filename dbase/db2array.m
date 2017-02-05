function [x, ixIncl, range, ixNotFound, ixNonSeries] = db2array(d, list, range, sw)
% db2array  Convert tseries database entries to numeric array.
%
% Syntax
% =======
%
%     [X, Incl, Range] = db2array(D)
%     [X, Incl, Range] = db2array(D, List)
%     [X, Incl, Range] = db2array(D, List, Range, ...)
%
%
% Input arguments
% ================
%
% * `D` [ struct ] - Input database with tseries objects that will be
% converted to a numeric array.
%
% * `List` [ char | cellstr ] - List of tseries names that will be
% converted to a numeric array; if not specified, all tseries
% entries found in the input database, `D`, will be included in the output
% arrays, `X`.
%
% * `Range` [ numeric | `Inf` ] - Date range; `Inf` means a range from the
% very first non-NaN observation to the very last non-NaN observation.
%
%
% Output arguments
% =================
%
% * `X` [ numeric ] - Numeric array with observations from individual
% tseries objects in columns.
%
% * `Incl` [ cellstr ] - List of tseries names that have been actually
% found in the database.
%
% * `Range` [ numeric ] - Date range actually used; this output argument is
% useful when the input argument `Range` is missing or `Inf`.
%
%
% Description
% ============
%
% The output array, `X`, is always NPer-by-NList-by-NAlt, where NPer is the
% length of the `Range` (the number of periods), NList is the number of
% tseries included in the `List`, and NAlt is the maximum number of columns
% that any of the tseries included in the `List` have.
%
% If all tseries data have the same size in 2nd and higher dimensions, the
% output array will respect that size in 3rd and higher dimensions. For
% instance, if all tseries data are NPer-by-2-by-5, the output array will
% be NPer-by-Nx-by-2-by-5. If some tseries data have unmatching size in 2nd
% or higher dimensions, the output array will be always a 3D array with all
% higher dimensions unfolded in 3rd dimension.
%
% If some tseries data have smaller size in 2nd or higher dimensions than
% other tseries entries, the last available column will be repeated for the
% missing columns.
%
%
% Example
% ========
%

% -IRIS Macroeconomic Modeling Toolbox.
% -Copyright (c) 2007-2017 IRIS Solutions Team.

%#ok<*VUNUS>
%#ok<*CTCH>

try
    list;
catch
    list = dbnames(d, 'classFilter=', 'tseries');
end

try
    range;
catch
    range = Inf;
end

try
    sw;
catch
    sw = struct( );
end

try
    sw.LagOrLead;
catch
    sw.LagOrLead = [ ];
end

try
    sw.IxLog;
catch
    sw.IxLog = [ ];
end

try
    sw.Warn;
catch
    sw.Warn = struct( );
end

try
    sw.Warn.NotFound;
catch
    sw.Warn.NotFound = true;
end

try
    sw.Warn.SizeMismatch;
catch
    sw.Warn.SizeMismatch = true;
end

try
    sw.Warn.FreqMismatch;
catch
    sw.Warn.FreqMismatch = true;
end

try
    sw.Warn.NonTseries;
catch
    sw.Warn.NonTseries = true;
end

try
    sw.Warn.NoRangeFound;
catch
    sw.Warn.NoRangeFound = true;
end

try, sw.BaseYear; catch, sw.BaseYear = @config; end

try, sw.ExpandMethod; catch, sw.ExpandMethod = 'RepeatLast'; end %#ok<*NOCOM>

% Swap `List` and `Range` if needed.
if isnumeric(list) && (iscellstr(range) || ischar(range))
    [list, range] = deal(range, list);
end

%--------------------------------------------------------------------------

if ischar(list)
    list = regexp(list, '\w+', 'match');
end
list = list(:).';

nList = length(list);
ixInvalid = false(1, nList);
ixIncl = false(1, nList);
ixFreqMismatch = false(1, nList);
ixNotFound = false(1, nList);
ixNonSeries = false(1, nList);

range2 = [ ];
if any(isinf(range([1, end])))
    range2 = dbrange(d, list);
    if isempty(range2)
        if sw.Warn.NoRangeFound
            utils.warning('dbase:db2array', ...
                ['Cannot determine range because ', ...
                'no tseries entries have been found in the database.']);
        end
        x = [ ];
        range = [ ];
        return
    end
end

if isinf(range(1))
    startDate = range2(1);
else
    startDate = range(1);
end

if isinf(range(end))
    endDate = range2(end);
else
    endDate = range(end);
end

range = startDate : endDate;
rangeFreq = datfreq(startDate);
nPer = numel(range);


% If all existing tseries have the same size in 2nd and higher dimensions, 
% reshape the output array to match that size. Otherwise, return a 2D
% array.
outpSize = [ ];
isReshape = true;

x = nan(nPer, 0);
for i = 1 : nList
    name = list{i};
    try
        nData = max(1, size(x, 3));
        if strcmp(name, '!ttrend')
            iX = [ ];
            getTtrend( );
            addData( );
        else
            field = d.(name);
            if istseries(field)
                iX = [ ];
                getTseriesData( );
                addData( );
            else
                ixNonSeries(i) = true;
            end
        end
    catch
        ixNotFound(i) = true;
        continue
    end
end

ixIncl = list(ixIncl);

throwWarning( );

if isempty(x)
    x = nan(nPer, nList);
end

if isReshape
    outpSize = [ size(x, 1), size(x, 2), outpSize ];
    x = reshape(x, outpSize);
end

return




    function getTseriesData( )
        tmpFreq = freq(field);
        if ~isnan(tmpFreq) && rangeFreq~=tmpFreq
            nData = max(1, size(x, 3));
            iX = nan(nPer, nData);
            ixFreqMismatch(i) = true;
        else
            k = 0;
            if ~isempty(sw.LagOrLead)
                k = sw.LagOrLead(i);
            end
            iX = rangedata(field, range+k);
            iSize = size(iX);
            iSize(1) = [ ];
            if isempty(outpSize)
                outpSize = iSize;
            else
                isReshape = isReshape && isequal(outpSize, iSize);
            end
            % Make sure iX is processed as 2D array.
            iX = iX(:, :);
        end
    end 




    function getTtrend( )
        k = 0;
        if ~isempty(sw.LagOrLead)
            k = sw.LagOrLead(i);
        end
        iX = dat2ttrend(range+k, sw.BaseYear);
        iX = iX(:);
    end 




    function addData( )
        if isempty(x)
            x = nan(nPer, nList, size(iX, 2));
        end
        iX = permute(iX, [1, 3, 2]);
        nAltX = size(x, 3);
        nAltXi = size(iX, 3);
        % If needed, expand number of alternatives in current array or current
        % addition.
        if nAltX==1 && nAltXi>1
            x = expand(x, nAltXi);
        elseif nAltX>1 && nAltXi==1
            iX = expand(iX, nAltX);
        end
        nAltX = size(x, 3);
        nAltXi = size(iX, 3);
        if nAltX==nAltXi
            if ~isempty(sw.IxLog) && sw.IxLog(i)
                iX = log(iX);
            end
            x(:, i, 1:nAltXi) = iX;
            ixIncl(i) = true;
        else
            ixInvalid(i) = true;
        end
        
        
        
        
        function x = expand(x, n)
            x = repmat(x, 1, 1, n);
            if strcmpi(sw.ExpandMethod, 'NaN')
                x(:, :, 2:end) = NaN;
            end
        end
    end 




    function throwWarning( )
        if sw.Warn.NotFound && any(ixNotFound)
            throw( ...
                exception.Base('Dbase:NameNotExist', 'warning'), ...
                list{ixNotFound} ...
                );
        end
        
        if sw.Warn.SizeMismatch && any(ixInvalid)
            throw( ...
                exception.Base('Dbase:EntrySizeMismatch', 'warning'), ...
                list{ixInvalid} ...
                );
        end
        
        if sw.Warn.FreqMismatch && any(ixFreqMismatch)
            throw( ...
                exception.Base('Dbase:EntryFrequencyMismatch', 'warning'), ...
                list{ixFreqMismatch} ...
                );
        end
        
        if sw.Warn.NonTseries && any(ixNonSeries)
            throw( ...
                exception.Base('Dbase:EntryNotSeries', 'warning'), ...
                list{ixNonSeries} ...
                );
        end
    end
end