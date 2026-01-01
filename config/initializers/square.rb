Square::Client.new(
  token: ENV["SQUARE_ACCESS_TOKEN"],
  base_url: Square::Environment::SANDBOX
)
