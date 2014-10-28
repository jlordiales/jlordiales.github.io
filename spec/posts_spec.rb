require 'yaml'
describe "Posts" do
  let(:posts) {Dir["_posts/**/*.md"]}

  it "should have comments enabled" do
    posts.each {|post| has_comments_enabled?(post) }
  end

  it "should have sharing enabled" do
    posts.each {|post| has_sharing_enabled?(post) }
  end

  it "uses the post layout" do
    posts.each {|post| uses_post_layout?(post) }
  end

  it "has jlordiales as author" do
    posts.each {|post| author_equals_to(post, "jlordiales") }
  end

  it "has a publication date" do
    posts.each {|post| has_a_publication_date?(post) }
  end

  it "has a title" do
    posts.each {|post| has_a_title?(post) }
  end


  def has_comments_enabled?(post_file)
    expect(front_matter(post_file)["comments"]).to eq(true), 
      "Post #{post_file} does not have comments enabled"
  end

  def has_sharing_enabled?(post_file)
    expect(front_matter(post_file)["share"]).to eq(true), 
      "Post #{post_file} does not have sharing enabled"
  end

  def uses_post_layout?(post_file)
    expect(front_matter(post_file)["layout"]).to eq("post"), 
      "Post #{post_file} does not have a post layout"
  end

  def author_equals_to(post_file, author)
    expect(front_matter(post_file)["author"]).to eq(author), 
      "Post #{post_file} does not have an author equal to #{author}"
  end

  def has_a_publication_date?(post_file)
    expect(front_matter(post_file)["date"]).to_not be_nil, 
      "Post #{post_file} does not have a publication date"
  end

  def has_a_title?(post_file)
    expect(front_matter(post_file)["title"]).to_not be_nil, 
      "Post #{post_file} does not have a title"
  end

  def front_matter(post_file)
    content = File.read(post_file)
    yaml_delimiter = "---"

    front_matter = content[/#{yaml_delimiter}(.*?)#{yaml_delimiter}/m, 1]
    YAML.load(front_matter)
  end
end
