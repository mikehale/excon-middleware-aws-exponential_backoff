module AWSErrorHelper
  def throttling_response
    body = %(
      <ErrorResponse xmlns="http://some-service.amazonaws.com/doc/2010-05-15/">
        <Error>
          <Type>Sender</Type>
          <Code>Throttling</Code>
          <Message>Rate exceeded</Message>
        </Error>
      </ErrorResponse>
    )

    Excon::Response.new(status: 400, body: body)
  end

  def request_time_too_skewed_response
    body = %(
      <Error>
        <Code>RequestTimeTooSkewed</Code>
        <Message>The difference between the request time and the current time is too large.</Message>
        <ServerTime>2006-11-10T13:43:55Z</ServerTime>
        <MaxAllowedSkewMilliseconds>900000</MaxAllowedSkewMilliseconds>
        <RequestTime>Fri, 10 Nov 2006 13:28:46 GMT</RequestTime>
      </Error>
    )

    Excon::Response.new(status: 400, body: body)
  end
end
