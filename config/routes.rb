WepimApp::Application.routes.draw do

  if Conf.manager?
    root :to => 'welcome#index'
    resource :admin_session
    match 'admin_logout' => 'admin_sessions#destroy', :as => :admin_logout
    match 'admin/new' => 'admin#new'
    match 'admin/edit' => 'admin#edit'
    match 'admin/create' => 'admin#create'
    match 'admin' => 'admin#index'
    match 'welcome/login' => 'welcome#login'
    match 'welcome/scenario' => 'welcome#start_scenario'
    match "welcome/shutdown/:id" => "welcome#shutdown"
    match 'welcome/start/:id' => "welcome#start"
    match 'welcome/redirect/:id' => "welcome#redirect"
    match 'welcome/refresh' => 'welcome#refresh'
    match 'welcome/killall' => "welcome#killall"
    match 'welcome' => 'welcome#index'
    match 'waiting/:id' => 'welcome#waiting', :as => :waiting
    match 'waiting/confirm/:id' => 'welcome#confirm_server_ready', :as => :confirm_server_ready
    match '/*else' => 'welcome#index'
  else
    root :to => 'users#index'
    match 'index' => 'users#index'
    match 'program' => 'program#index', :as => :program
    match 'engine' => 'engine#index', :as => :engine
    match 'wepic' => 'wepic#index', :as => :wepic
    resources :pictures do
      member do
        get :images
      end
    end
    resources :query
    match 'query/insert' => 'query#insert'
    match 'contacts/:username/pictures' => 'pictures#contact'
    match 'wepic/update' => 'wepic#update'
    match 'pictures/update' => 'pictures#update'
    match 'wepic/comments/latest' => 'wepic#getLatestComments'
    match 'wepic/comments/add' => 'wepic#addComment'
    match 'wepic/comments/remove' => 'wepic#removeComment'
    match 'wepic/send' => 'wepic#send_picture'
  end
  resources :users, :user_sessions
  match 'login' => 'user_sessions#new', :as => :login
  match 'logout' => 'user_sessions#destroy', :as => :logout
  match 'list' => 'users#list'
  match 'admin' => 'admin#index', :as => :admin

  # The priority is based upon order of creation:
  # first created -> highest priority.

  # The priority is based upon order of creation: first created -> highest
  # priority.
  # Naming routes with :as see
  # http://guides.rubyonrails.org/routing.html#naming-routes
end
