class CheckListsController < ApplicationController
  include Shared::ListsModule
  
  before_filter :login_required, :except => [:index, :show, :taxa]
  before_filter :load_list, :only => [:show, :edit, :update, :destroy, :compare, :remove_taxon, :add_taxon_batch, :taxa]
  before_filter :require_editor, :only => [:edit, :update, :destroy, :remove_taxon, :add_taxon_batch]
  before_filter :lock_down_default_check_lists, :only => [:edit, :update, :destroy]
  before_filter :load_find_options, :only => [:show]
  
  # Not supporting any of these just yet
  def index; redirect_to '/'; end
  
  def show
    @place = @list.place
    @other_check_lists = @place.check_lists.paginate(:page => 1)
    @other_check_lists.delete_if {|l| l.id == @list.id}
    
    # If this is a place's default check list, load ALL the listed taxa
    # belonging to this place.  Kind of weird, I know.  The alternative would
    # be to keep the default list updated with duplicates from all the other
    # check lists belonging to a place, like we do with parent lists.  It 
    # would be a pain to manage, but it might be faster.
    if @list.is_default?
      @find_options[:conditions] = update_conditions(
        @find_options[:conditions], ["AND place_id = ?", @list.place_id])
      
      # Make sure we don't get duplicate taxa from check lists other than the default
      @find_options[:group] = "listed_taxa.taxon_id"
      
      # Searches must use place_id instead of list_id for default checklists 
      # so we can search items in other checklists for this place
      if @q = params[:q]
        @taxa = Taxon.search(@q, 
          :with => {:places => @list.place_id},
          :page => @find_options[:page], 
          :per_page => @find_options[:per_page])
        @find_options[:conditions] = List.merge_conditions(
          @find_options[:conditions], ["listed_taxa.taxon_id IN (?)", @taxa])
      end
      @listed_taxa = ListedTaxon.paginate(@find_options)
      
      @total_listed_taxa = ListedTaxon.count('DISTINCT(taxon_id)',
        :conditions => ["place_id = ?", @list.place_id])
      
      if logged_in?
        @total_observed_taxa = current_user.observations.count(
          'DISTINCT(taxon_id)',
          :conditions => ["taxon_id IN (?)", @list.taxon_ids])
      end
    end
    super
  end
  
  def new
    unless @place = Place.find_by_id(params[:place_id])
      flash[:notice] = <<-EOT
        Check lists must belong to a place. To create a new check list, visit
        a place's default check list and click the 'Create a new check list'
        link.
      EOT
      return redirect_to places_path
    end
    
    @taxon = Taxon.find_by_id(params[:taxon_id])
    @iconic_taxa = Taxon.iconic_taxa
    @check_list = CheckList.new(:place => @place, :taxon => @taxon)
  end
  
  def create
    @check_list = CheckList.new(params[:check_list])
    
    # Override taxon choice with iconic taxon choice
    if params[:iconic_taxon] && (iconic_taxon = Taxon.find_by_id(params[:iconic_taxon][:id]))
      @check_list.taxon = iconic_taxon
    end
    
    # add rules for all selected taxa
    if @check_list.taxon_id
      update_rules(@check_list, {:taxa => [{:taxon_id => @check_list.taxon_id}]})
    end
    
    respond_to do |format|
      if @check_list.save
        flash[:notice] = 'List was successfully created.'
        format.html { redirect_to(@check_list) }
      else
        @taxon = @check_list.taxon
        @iconic_taxa = Taxon.iconic_taxa
        format.html { render :action => "new" }
      end
    end
  end
  
  def edit
    @iconic_taxa = Taxon::ICONIC_TAXA || Taxon.iconic_taxa.all
  end
  
  def update
    if @list.update_attributes(params[:check_list])
      flash[:notice] = "Check list updated!"
      return redirect_to @list
    else
      @iconic_taxa = Taxon::ICONIC_TAXA || Taxon.iconic_taxa.all
      render :action => 'edit'
    end
  end
  
  private
  
  def load_list
    @list = CheckList.find_by_id(params[:id])
    render_404 && return unless @list
    true
  end
  
  def lock_down_default_check_lists
    if @list.is_default?
      flash[:error] = "You can't do that for the default check list of a place!"
      redirect_to @list
    end
  end
  
  def get_iconic_taxon_counts(list, iconic_taxa = nil)
    iconic_taxa ||= Taxon::ICONIC_TAXA
    iconic_taxon_counts_by_id_hash = if list.is_default?
      ListedTaxon.count('DISTINCT(taxon_id)', :group => "taxa.iconic_taxon_id",
        :joins => "JOIN taxa ON taxa.id = listed_taxa.taxon_id",
        :conditions => ["place_id = ?", list.place_id])
    else
      list.listed_taxa.count(:all, :include => [:taxon], :group => "taxa.iconic_taxon_id")
    end
    iconic_taxa.map do |iconic_taxon|
      [iconic_taxon, iconic_taxon_counts_by_id_hash[iconic_taxon.id.to_s]]
    end
  end
end
