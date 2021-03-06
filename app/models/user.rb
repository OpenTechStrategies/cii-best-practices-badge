class User < ActiveRecord::Base
  before_save { self.email = email.downcase }
  has_secure_password
  has_many :projects, dependent: :destroy
  attr_accessor :remember_token

  MIN_PASSWORD_LENGTH = 7

  validates :name, presence: true, length: { maximum: 50 }
  validates :email, presence: true, length: { maximum: 255 },
                    uniqueness: { case_sensitive: false }, email: true
  validates :password, presence: true,
                       length: { minimum: MIN_PASSWORD_LENGTH }

  # Returns the hash digest of the given string.
  def self.digest(string)
    cost = if ActiveModel::SecurePassword.min_cost
             BCrypt::Engine::MIN_COST
           else
             BCrypt::Engine.cost
           end
    BCrypt::Password.create(string, cost: cost)
  end

  def self.create_with_omniauth(auth)
    @user = User.new(provider: auth['provider'], uid: auth['uid'],
                     name: auth['info']['name'], email: auth['info']['email'],
                     nickname: auth['info']['nickname'])
    @user.save(validate: false)
    @user
  end

  def admin?
    role == 'admin'
  end

  # Returns a random token
  def self.new_token
    SecureRandom.urlsafe_base64
  end

  # Remembers a user in the database for use in persistent sessions
  def remember
    self.remember_token = User.new_token
    update_attribute(:remember_digest, User.digest(remember_token))
  end

  # Returns true if the given token matches the digest
  def authenticated?(remember_token)
    return false if remember_digest.nil?
    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  # Forgets a user
  def forget
    update_attribute(:remember_digest, nil)
  end
end
