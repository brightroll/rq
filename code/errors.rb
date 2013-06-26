module RQ
  class RqError < ::StandardError; end
  class RqCannotRelay < RqError; def message; 'Cannot relay message'; end; end
  class RqQueueNotFound < RqError; def message; 'Queue not found'; end; end
  class RqMissingArgument < RqError; def message; 'Missing argument'; end; end
end
