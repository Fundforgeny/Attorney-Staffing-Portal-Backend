# This class serves as the base for most of the Devise controllers that
# handle API requests. It provides common functionality via the included concern.
#
# Note: The SessionsController does NOT inherit from this class.
class Users::BaseDeviseController < DeviseController
  include Users::SharedDeviseMethods
end
