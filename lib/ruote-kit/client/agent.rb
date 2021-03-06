module RuoteKit
  module Client

    # This wrapper around rufus-jig
    class Agent

      # URL to a running ruote-kit
      attr_reader :url
      attr_reader :path

      def initialize( url )
        @url = URI.parse( url )
        @path = @url.path
        @path = @path[0..-2] if(@path[-1] == '/')
      end

      # Launch the process specified in the #RuoteKit::Client::LaunchItem.
      # Returns a #RuoteKit::Client::Process instance of the newly launched process
      def launch_process( launch_item_or_definition_or_uri, fields = {} )
        launch_item = if launch_item_or_definition_or_uri.kind_of?(RuoteKit::Client::LaunchItem)
          launch_item_or_definition_or_uri
        else
          LaunchItem.new(launch_item_or_definition_or_uri, fields)
        end

        raise RuoteKit::Client::Exception, "Launch item not valid" unless launch_item.valid?

        response = jig.post(
          @path + '/processes',
          launch_item.to_json,
          :content_type => 'application/json', :accept => 'application/json'
        )

        raise RuoteKit::Client::Exception, "Invalid response from ruote-kit" if response.nil? or response['launched'].nil?

        find_process(response['launched'])
      end

      # Return the list of processes
      def processes
        response = jig.get(@path + '/processes', :accept => 'application/json')

        response['processes'].map { |p| Process.new(p) }.each { |p| p.agent = self }
      end

      # Cancel a process
      def cancel_process( wfid )
        jig.delete( @path + "/processes/#{wfid}", :accept => 'application/json' )
      end

      # Kill a process
      def kill_process( wfid )
        jig.delete( @path + "/processes/#{wfid}?_kill=1", :accept => 'application/json' )
      end

      def workitems( options = {} )
        path = @path + "/workitems"
        
        if(options[:process])
          path << "/#{options[:process].wfid}"
        elsif(options[:wfid])
          path << "/#{options[:wfid]}"
        end

        params = {}
        if options[:participant]
          parts = [ options[:participant] ].flatten
          params['participant'] = parts.join(',')
        end

        if options[:fields]
          options[:fields].each do |k,v|
            v = CGI::escape(Rufus::Json.encode({"value" => v})) unless v.kind_of?(String)
            params[k.to_s] = v
          end
        end

        response = jig.get( path, :accept => 'application/json', :params => params )

        response['workitems'].map { |w| Workitem.new(w) }.each { |w| w.agent = self }
      end

      def find_process(wfid)
        response = jig.get(@path + "/processes/#{wfid}", :accept => 'application/json')

        raise RuoteKit::Client::Exception, "Invalid response from ruote-kit" if response.nil? or response['process'].nil?

        p = Process.new(response['process'])
        p.agent = self
        p
      end

      def find_workitem(wfid, expid)
        response = jig.get(@path + "/workitems/#{wfid}/#{expid}", :accept => 'application/json')

        raise RuoteKit::Client::Exception, "Invalid response from ruote-kit" if response.nil? or response['workitem'].nil?

        w = Workitem.new(response['workitem'])
        w.agent = self
        w
      end

      def update_workitem!(workitem)
        put_workitem(workitem['fei']['wfid'], workitem['fei']['expid'], 'fields' => workitem['fields'])
      end

      def update_workitem(workitem)
        begin
          update_workitem!(workitem)
        rescue
          false
        end
      end

      def proceed_workitem!(workitem)
        put_workitem(workitem['fei']['wfid'], workitem['fei']['expid'], 'fields' => workitem['fields'], '_proceed' => '1')
      end

      def proceed_workitem(workitem)
        begin
          proceed_workitem!(workitem)
        rescue
          false
        end
      end

      def expressions(process)
        response = jig.get(@path + "/expressions/#{process.wfid}", :accept => 'application/json')

        raise RuoteKit::Client::Exception, "Invalid response from ruote-kit" if response.nil? or response['expressions'].nil?

        response['expressions'].map { |e| Expression.new(e) }.each { |e| e.agent = self }
      end

      def find_expression(wfid, expid)
        response = jig.get(@path + "/expressions/#{wfid}/#{expid}", :accept => 'application/json')

        raise RuoteKit::Client::Exception, "Invalid response from ruote-kit" if response.nil? or response['expression'].nil?

        e = Expression.new(response['expression'])
        e.agent = self
        e
      end

      def cancel_expression(expression)
        delete_expression(expression.wfid, expression.expid)
      end

      def kill_expression(expression)
        delete_expression(expression.wfid, expression.expid, '_kill' => '1')
      end

      private

      def jig
        @jig ||= Rufus::Jig::Http.new( @url.host, @url.port, {:prefix => (@url.path.empty? || @url.path == '/') ? nil : @url.path } )
      end

      def put_workitem(wfid, expid, data)
        response = jig.put(@path + "/workitems/#{wfid}/#{expid}", data, :accept => 'application/json', :content_type => 'application/json')
        if(response and response['workitem'] and response['workitem']['fields'] == data['fields'])
          true
        else
          # some error occured. for now, raise an exception
          raise RuoteKit::Client::Exception, 'Error while updating workitem at ruote-kit'
        end
      end

      def delete_expression(wfid, expid, params = {})
        response = jig.delete(@path + "/expressions/#{wfid}/#{expid}", :accept => 'application/json', :params => params)
        if(response and response['status'] and response['status'] == 'ok')
          true
        else
          raise RuoteKit::Client::Exception, 'Error while deleting expression at ruote-kit'
        end
      end
    end
  end
end
