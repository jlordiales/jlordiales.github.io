require 'yaml'

describe "Jekyll configuration" do
  let(:config_yaml) {YAML.load_file("_config.yml")}

  it "has the permaling format as year/month/day/title" do
    expect(config_yaml["permalink"]).to eq("/:year/:month/:day/:title")
  end

  it "has the url set to the correct domain" do
    expect(config_yaml["url"]).to eq("http://jlordiales.me")
  end

end
