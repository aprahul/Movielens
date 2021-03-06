if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(data.table)) install.packages("data.table", repos = "http://cran.us.r-project.org")

library(tidyverse)
library(caret)
library(data.table)
library(lubridate)
library(Matrix.utils)
library(DT)
library("latexpdf")
library("tinytex")

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)

ratings <- fread(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
col.names = c("userId", "movieId", "rating", "timestamp"))

movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")

# if using R 3.6 or earlier:
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
title = as.character(title),genres = as.character(genres))


movielens <- left_join(ratings, movies, by = "movieId")

# Validation set will be 10% of MovieLens data
set.seed(1, sample.kind="Rounding") # if using R 3.5 or earlier, use `set.seed(1)`
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId and movieId in validation set are also in edx set
validation <- temp %>% 
semi_join(edx, by = "movieId") %>%
semi_join(edx, by = "userId")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)

edx_test_index <- createDataPartition(y = edx$rating, times = 1, p = 0.2, list = FALSE)
edx_test <- edx[-edx_test_index,]
edx_train <- edx[edx_test_index,]

rm(dl, ratings, movies, test_index, temp, movielens, removed)


# -- The MovieLens Evaluation --- #

# Part-1 - Data Exploration and Analysis
# How many features and observations present in edx_train dataset ?
glimpse(edx_train)

#How these Features are summarused for Standard deviation and Median values ?
summary(edx_train)

#What is the count of the primary Feature (rating) consideration ?
table(edx_train$rating)

# Part-2 - Data Visualization and Analysis

# What rating show a high count ?
edx_train %>% group_by(rating) %>% summarize(count = n()) %>%
ggplot(aes(x = rating, y = count)) +
geom_line()

# Which single genre has more ratings ?
t_genr <- edx_train %>% separate_rows(genres) %>%  group_by(genres) %>%
summarize(count = n()) %>% arrange(desc(count))
t_genr

# What are the top-10 titles with highest rating ?
top_10_titles <- edx_train %>% group_by(title) %>%  summarize(count=n()) %>%  top_n(10,count) %>%
arrange(desc(count))
top_10_titles

# Is there a qualitative relation between Genre and Title ?
edx_train %>% group_by(title,genres) %>%
summarize(count=n()) %>%
top_n(20,count) %>%
arrange(desc(count))

# Is there a relation between MovieId and rating ?
edx_train %>% count(movieId) %>%  
ggplot(aes(n)) +  geom_histogram( bins=30, color = "black") +
scale_x_log10() + ggtitle("Movies") + labs(x="movieId", y="number of ratings")

# Is there a quantitative relation between UserId and rating ?
edx_train %>% count(userId) %>% 
ggplot(aes(n)) + geom_histogram( bins=30, color = "black") +
scale_x_log10() + ggtitle("Users") + labs(x="userId" , y="number of ratings")

# Part-3 - Model Evaluations and Results
# Core function to evaluate :
rmse <- function(true_ratings, predicted_ratings){
sqrt(mean((true_ratings - predicted_ratings)^2))
}

# Defining the coefficients based on the training data:
# Step-1 : To calculate the average of all ratings of the edx set
mu <- mean(edx$rating)

# Step-2a : To calculate the coefficient (b_i) based on MovieId as factor.
mov_avg <- edx %>% group_by(movieId) %>% 
summarize(b_i = mean(rating - mu))

# Step-2b : Prepare data for predicting based on the above coefficient ( predicted ratings )
pred_bi <- mu + validation %>% 
left_join(mov_avg, by='movieId') %>% .$b_i

# Step-3a : To calculate the coefficient (b_usr) using traning data by adding another factor (MovieId+UserId)
user_avg <- edx %>%  left_join(mov_avg, by='movieId') %>% group_by(userId) %>%
summarize(b_usr = mean(rating - mu - b_i))

# Step-3b : Prepare data for predicting based on the above coefficient ( predicted ratings )
pred_bu <- validation %>% left_join(mov_avg, by='movieId') %>%
left_join(user_avg, by='userId') %>%
mutate(pred = mu + b_i + b_usr) %>%
.$pred

# Step-4a : To calculate the coefficient by adding  3rd factor (MovieId+UserId+ Time)
#For this we need to work on the Validation set and convert the timestamp to datetime object.
valid <- validation
valid <- valid %>% mutate(date = round_date(as_datetime(timestamp), unit = "week"))

# Now to calculate the 'Time' effect coefficient (b_t):
temp_avgs <- edx %>%
left_join(mov_avg, by='movieId') %>%
left_join(user_avg, by='userId') %>%
mutate(date = round_date(as_datetime(timestamp), unit = "week")) %>%
group_by(date) %>%
summarize(b_t = mean(rating - mu - b_i - b_usr))

#Step-4b : Prepare data for predicting based on the above coefficient ( predicted ratings )
pred_bt <- valid %>% 
left_join(mov_avg, by='movieId') %>%
left_join(user_avg, by='userId') %>%
left_join(temp_avgs, by='date') %>%
mutate(pred = mu + b_i + b_usr + b_t) %>%
.$pred

# Evaluations and Results : Calculate the RMSE for movies, users and time effects
rmse_mod1 <- rmse(validation$rating,pred_bi)  
rmse_mod1

rmse_mod2 <- rmse(validation$rating,pred_bu)
rmse_mod2

rmse_mode3 <- rmse(valid$rating,pred_bt)
rmse_mode3

# Now using Regularization to optimise the coefficiants
lambdas <- seq(0, 10, 0.25)

rmses <- sapply(lambdas, function(l){
  
  mu_reg <- mean(edx$rating)
  
b_i_reg <- edx %>% 
group_by(movieId) %>%
summarize(b_i_reg = sum(rating - mu_reg)/(n()+l), .groups = 'drop')
  
b_u_reg <- edx %>% 
left_join(b_i_reg, by="movieId") %>%
group_by(userId) %>%
summarize(b_u_reg = sum(rating - b_i_reg - mu_reg)/(n()+l), .groups = 'drop')
  
pred_b_i_u <- 
validation %>% 
left_join(b_i_reg, by = "movieId") %>%
left_join(b_u_reg, by = "userId") %>%
mutate(pred = mu_reg + b_i_reg + b_u_reg) %>%
.$pred
  
return(rmse(validation$rating,pred_b_i_u))
})

# To visualize the lambda versus rmses
qplot(lambdas, rmses)

# To find Minimum value of lambda
lambda <- lambdas[which.min(rmses)]
lambda

# To find Minimum value of rmses
rmse_mod4 <- min(rmses)
rmse_mod4

# To consolidate and compare the results
#rmse_results <- data.frame(methods=c("movie effect","movie + user effects","movie + user + time effects", "Regularized Movie + User Effect Model"), rmse = c(rmse_model1, rmse_model2,rmse_model3, rmse_model4))
#rmse_results
