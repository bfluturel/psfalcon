class Falcon {
    [string] $Hostname
    [string] $ClientId
    [string] $ClientSecret
    [string] $MemberCid
    [string] $Token
    [datetime] $Expires
    [hashtable] $Endpoints
    [hashtable] $ItemTypes
    [hashtable] $Parameters
    [hashtable] $Patterns
    [hashtable] $Schema
    [System.Globalization.TextInfo] $Culture
    Falcon ($Data) {
        # Ingest input data generated by Falcon.psm1 and determine culture for dynamic parameter naming
        $this.Culture = (Get-Culture).TextInfo
        $this.Endpoints = $Data.Endpoints
        $this.ItemTypes = $Data.ItemTypes
        $this.Parameters = $Data.Parameters
        $this.Patterns = $Data.Patterns
        $this.Schema = $Data.Schema
        $this.PSObject.TypeNames.Insert(0,'Falcon')
    }
    [hashtable] GetEndpoint([string] $Endpoint) {
        # Output endpoint information
        $Path = $Endpoint.Split(':')[0]
        $Method = $Endpoint.Split(':')[1]
        if (-not($Path -and $Method)) {
            throw "Invalid endpoint: '$Endpoint'"
        }
        $Output = @{
            path = $Path
            method = $Method
        }
        # Gather endpoint properties
        $Default = $this.Endpoints.$Path.$Method.Clone()
        if (-not $Default.consumes -and $Default.parameters.schema) {
            # Force 'application/json' for 'content-type' with body parameters
            $Default['consumes'] = "application/json"
        }
        $Default.GetEnumerator().foreach{
            $Value = if ($_.Key -eq 'parameters') {
                $Parameters = @{}
                ($_.Value).GetEnumerator().foreach{
                    if ($_.Key -eq 'schema') {
                        $this.GetSchema($_.Value).GetEnumerator().foreach{
                            # Use shared parameter sets from schema
                            $Parameters[$_.Key] = $_.Value
                            if ($Default.Parameters.($_.Key)) {
                                # Update with manually defined endpoint values
                                $Name = $_.Key
                                $Default.Parameters.$Name.GetEnumerator().foreach{
                                    $Parameters.$Name[$_.Key] = $_.Value
                                }
                            }
                        }
                    }
                    elseif ($this.Parameters.($_.Key)) {
                        # Use shared parameter properties
                        $Parameters[$_.Key] = $this.Parameters.($_.Key).Clone()
                        if ($Default.Parameters.($_.Key)) {
                            # Update with manually defined endpoint values
                            $Name = $_.Key
                            $Default.Parameters.$Name.GetEnumerator().foreach{
                                $Parameters.$Name[$_.Key] = $_.Value
                            }
                        }
                    }
                    else {
                        # Use endpoint parameter properties
                        $Parameters[$_.Key] = $_.Value
                    }
                }
                $Parameters.GetEnumerator().foreach{
                    if (($_.Key -match '^(id|ids)$') -and (-not $_.Value.pattern)) {
                        # Append default RegEx pattern by endpoint
                        $_.Value['pattern'] = $this.GetPattern($Endpoint)
                    }
                    if (-not $_.Value.dynamic) {
                        # Generate dynamic parameter name
                        $_.Value['dynamic'] = $this.Culture.ToTitleCase($_.Key) -replace '[^a-zA-Z0-9]',''
                    }
                    # Update description with ItemType and add ParameterSetName
                    $_.Value['description'] = $this.GetItemType($Endpoint, $_.Value.description)
                    $_.Value['set'] = $Endpoint
                }
                $Parameters
            }
            elseif ($_.Key -eq 'description') {
                $this.GetItemType($Endpoint, $_.Value)
            }
            else {
                $_.Value
            }
            $Output[$_.Key] = $Value
        }
        return $Output
    }
    [string] GetItemType([string] $Endpoint, [string] $Value) {
        $Output = if ($Value -match '\{0\}') {
            $ItemType = $this.ItemTypes.GetEnumerator().Where({ $Endpoint -match $_.Key }).Value
            $Value -f $ItemType
        }
        else {
            $Value
        }
        return $Output
    }
    [string] GetPattern([string] $Endpoint) {
        # Match Endpoint to Patterns
        return $this.Patterns.GetEnumerator().Where({ $Endpoint -match $_.Key }).Value
    }
    [string] GetResponse([string] $Endpoint, [int] $Code) {
        # Gather Endpoint.Responses and output response type
        $Path = $Endpoint.Split(':')[0]
        $Method = $Endpoint.Split(':')[1]
        if (-not($Path -and $Method)) {
            throw "Invalid endpoint: '$Endpoint'"
        }
        $Responses = $this.Endpoints.$Path.$Method.responses
        $Output = $Responses.GetEnumerator().Where({ $_.Value -contains $Code }).Key
        if ($Output) {
            return $Output
        }
        else {
            return $Responses.default
        }
    }
    [hashtable] GetSchema([string] $Schema) {
        # Gather schema and output all references as a single parameter set
        $Output = @{}
        $this.Schema.$Schema.GetEnumerator().foreach{
            if ($_.Value.schema) {
                $Parent = $_.Key
                $this.GetSchema($_.Value.schema).GetEnumerator().foreach{
                    $Output[$_.Key] = $_.Value
                    $Output.($_.Key)['parent'] = $Parent
                }
            }
            else {
                $Output[$_.Key] = $_.Value
            }
        }
        return $Output
    }
    [string] Rfc3339($Int) {
        # Convert number of hours into an RFC-3339 string
        return "$([Xml.XmlConvert]::ToString((Get-Date).AddHours($Int),[Xml.XmlDateTimeSerializationMode]::Utc))"
    }
}